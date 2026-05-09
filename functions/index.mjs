import {onCall, HttpsError} from 'firebase-functions/v2/https';
import admin from 'firebase-admin';
import {SecretManagerServiceClient} from '@google-cloud/secret-manager';
import {
  assertNoDirectIdentity,
  studyPatientId,
  validateDoctorPackagePayload,
  validateResearchExportPayload,
} from './src/validation.mjs';

admin.initializeApp();

const db = admin.firestore();
const secretClient = new SecretManagerServiceClient();

export const submitDoctorPackage = onCall({region: 'asia-south1'}, async (request) => {
  const actor = await requireActiveRole(request.auth, ['asha', 'admin']);
  const payload = request.data;
  try {
    validateDoctorPackagePayload(payload);
  } catch (error) {
    throw new HttpsError('failed-precondition', error.message);
  }

  const assessment = payload.assessment;
  const caseId = `${assessment.patientHash}-${assessment.visitId}`.replace(
    /[^a-zA-Z0-9_-]/g,
    '_',
  );
  const consentId = `consent-${assessment.visitId}`;
  const packageId = `doctor-${assessment.visitId}`;
  const now = admin.firestore.FieldValue.serverTimestamp();

  const batch = db.batch();
  batch.set(db.doc(`cases/${caseId}`), {
    caseId,
    visitId: assessment.visitId,
    patientHash: assessment.patientHash,
    state: payload.patient.state || '',
    district: payload.patient.district || '',
    villageCode: payload.clinical?.villageCode || '',
    createdByUid: actor.uid,
    assignedDoctorUid: payload.assignedDoctorUid,
    riskLevel: assessment.carePlan?.action || 'unknown',
    recommendedAction: assessment.carePlan?.action || 'unknown',
    status: 'queued',
    updatedAt: now,
    createdAt: now,
  }, {merge: true});
  batch.set(db.doc(`cases/${caseId}/private/patientIdentity`), {
    ...payload.patient,
    consentId,
    createdAt: now,
  }, {merge: true});
  batch.set(db.doc(`cases/${caseId}/consents/${consentId}`), {
    ...payload.consent,
    consentId,
    ashaUid: actor.uid,
    serverRecordedAt: now,
  }, {merge: true});
  batch.set(db.doc(`cases/${caseId}/screenings/${assessment.visitId}`), {
    ...assessment,
    uploadedAt: now,
  }, {merge: true});
  batch.set(db.doc(`cases/${caseId}/doctorPackages/${packageId}`), {
    packageId,
    visitId: assessment.visitId,
    doctorUid: payload.assignedDoctorUid,
    ashaUid: actor.uid,
    status: 'queued',
    doctorBrief: assessment.carePlan?.doctorBrief || '',
    imageRefs: payload.imageReferences || [],
    consentId,
    createdAt: now,
  }, {merge: true});
  batch.set(db.collection('auditEvents').doc(), {
    actorUid: actor.uid,
    role: actor.role,
    action: 'doctor_package_submitted',
    caseId,
    visitId: assessment.visitId,
    result: 'allowed',
    createdAt: now,
  });
  await batch.commit();
  return {caseId, packageId};
});

export const submitResearchExport = onCall({region: 'asia-south1'}, async (request) => {
  const actor = await requireActiveRole(request.auth, ['research', 'admin']);
  const payload = request.data;
  try {
    validateResearchExportPayload(payload);
  } catch (error) {
    throw new HttpsError('failed-precondition', error.message);
  }

  const exportRow = payload.export || payload;
  const secret = await accessSecret('research-pseudonym-secret');
  const exportId = `research-${exportRow.visitId}`;
  const serverStudyPatientId = studyPatientId({
    secret,
    patientHash: exportRow.patientHash || payload.patientHash,
    visitId: exportRow.visitId,
  });
  const metadata = {
    ...exportRow,
    studyPatientId: serverStudyPatientId,
    exportId,
    status: 'accepted',
    submittedByUid: actor.uid,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  };
  assertNoDirectIdentity(metadata);
  await db.doc(`researchExports/${exportId}`).set(metadata, {merge: true});
  return {exportId, status: 'accepted'};
});

async function requireActiveRole(auth, allowedRoles) {
  if (!auth?.uid) {
    throw new HttpsError('unauthenticated', 'Authentication is required.');
  }
  const snapshot = await db.doc(`users/${auth.uid}`).get();
  const profile = snapshot.data();
  if (!profile?.active || !allowedRoles.includes(profile.role)) {
    throw new HttpsError('permission-denied', 'Role is not allowed.');
  }
  return {uid: auth.uid, role: profile.role};
}

async function accessSecret(secretId) {
  const project = process.env.GCLOUD_PROJECT || process.env.GCP_PROJECT;
  if (!project) {
    throw new HttpsError('failed-precondition', 'GCP project is unavailable.');
  }
  const [version] = await secretClient.accessSecretVersion({
    name: `projects/${project}/secrets/${secretId}/versions/latest`,
  });
  return version.payload.data.toString('utf8');
}
