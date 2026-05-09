import crypto from 'node:crypto';

const directIdentityKeys = new Set([
  'fullName',
  'phone',
  'dateOfBirth',
  'dob',
  'pinCode',
  'village',
]);

export function validateConsentAfterResult(consent) {
  if (!consent || typeof consent !== 'object') {
    throw new Error('Consent is required.');
  }
  const scopes = Array.isArray(consent.scopes) ? consent.scopes : [];
  if (scopes.length === 0) {
    throw new Error('Consent must contain at least one scope.');
  }
  const recordedAt = new Date(consent.recordedAt);
  const completedAt = new Date(consent.screeningCompletedAt);
  if (Number.isNaN(recordedAt.getTime()) || Number.isNaN(completedAt.getTime())) {
    throw new Error('Consent dates are invalid.');
  }
  if (recordedAt < completedAt) {
    throw new Error('Consent must be recorded after screening completion.');
  }
  return scopes;
}

export function requireConsentScope(consent, scope) {
  const scopes = validateConsentAfterResult(consent);
  if (!scopes.includes(scope)) {
    throw new Error(`Consent missing required scope: ${scope}`);
  }
}

export function assertNoDirectIdentity(payload, path = []) {
  if (Array.isArray(payload)) {
    payload.forEach((item, index) => assertNoDirectIdentity(item, [...path, index]));
    return;
  }
  if (!payload || typeof payload !== 'object') {
    return;
  }
  for (const [key, value] of Object.entries(payload)) {
    const nextPath = [...path, key];
    if (directIdentityKeys.has(key)) {
      throw new Error(`Direct identity field found at ${nextPath.join('.')}`);
    }
    assertNoDirectIdentity(value, nextPath);
  }
}

export function validateDoctorPackagePayload(payload) {
  if (!payload || typeof payload !== 'object') {
    throw new Error('Doctor package payload is required.');
  }
  requireConsentScope(payload.consent, 'doctorShare');
  if (!payload.patient || typeof payload.patient !== 'object') {
    throw new Error('Doctor package requires private patient identity.');
  }
  if (!payload.assessment || typeof payload.assessment !== 'object') {
    throw new Error('Doctor package requires assessment.');
  }
  if (!payload.assignedDoctorUid || typeof payload.assignedDoctorUid !== 'string') {
    throw new Error('Doctor package requires assignedDoctorUid.');
  }
  assertNoDirectIdentity(payload.assessment);
  assertNoDirectIdentity(payload.clinical || {});
}

export function validateResearchExportPayload(payload) {
  if (!payload || typeof payload !== 'object') {
    throw new Error('Research export payload is required.');
  }
  requireConsentScope(payload.consent, 'researchExport');
  assertNoDirectIdentity(payload.export || payload);
  if (!payload.visitId && !(payload.export && payload.export.visitId)) {
    throw new Error('Research export requires visitId.');
  }
}

export function studyPatientId({secret, patientHash, visitId}) {
  if (!secret || !patientHash) {
    throw new Error('Secret and patientHash are required.');
  }
  return crypto
    .createHmac('sha256', secret)
    .update(`${patientHash}|${visitId || ''}`)
    .digest('hex');
}
