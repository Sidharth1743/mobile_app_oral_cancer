import assert from 'node:assert/strict';
import {describe, it} from 'node:test';
import {
  assertNoDirectIdentity,
  requireConsentScope,
  studyPatientId,
  validateDoctorPackagePayload,
  validateResearchExportPayload,
} from '../src/validation.mjs';

describe('Cloud function validation', () => {
  it('accepts doctor package only with post-result doctor consent', () => {
    assert.doesNotThrow(() => validateDoctorPackagePayload(doctorPackage()));
    assert.throws(
      () => validateDoctorPackagePayload({
        ...doctorPackage(),
        consent: consent(['researchExport']),
      }),
      /doctorShare/,
    );
  });

  it('rejects direct identity outside private patient package section', () => {
    assert.throws(
      () => validateDoctorPackagePayload({
        ...doctorPackage(),
        assessment: {
          ...doctorPackage().assessment,
          phone: '9999999999',
        },
      }),
      /Direct identity/,
    );
    assert.throws(
      () => assertNoDirectIdentity({nested: [{fullName: 'Meera'}]}),
      /nested.0.fullName/,
    );
  });

  it('accepts research export only with research consent and stable secret HMAC', () => {
    const payload = {
      visitId: 'visit-1',
      patientHash: 'patient-hash',
      consent: consent(['researchExport']),
      export: {
        visitId: 'visit-1',
        patientHash: 'patient-hash',
        ageBand: '45-54',
      },
    };

    assert.doesNotThrow(() => validateResearchExportPayload(payload));
    assert.equal(
      studyPatientId({
        secret: 'secret-a',
        patientHash: 'patient-hash',
        visitId: 'visit-1',
      }),
      studyPatientId({
        secret: 'secret-a',
        patientHash: 'patient-hash',
        visitId: 'visit-1',
      }),
    );
    assert.notEqual(
      studyPatientId({
        secret: 'secret-a',
        patientHash: 'patient-hash',
        visitId: 'visit-1',
      }),
      studyPatientId({
        secret: 'secret-b',
        patientHash: 'patient-hash',
        visitId: 'visit-1',
      }),
    );
  });

  it('rejects consent recorded before screening completion', () => {
    assert.throws(
      () =>
        requireConsentScope(
          {
            scopes: ['doctorShare'],
            recordedAt: '2026-05-03T08:00:00.000Z',
            screeningCompletedAt: '2026-05-03T09:00:00.000Z',
          },
          'doctorShare',
        ),
      /after screening/,
    );
  });
});

function doctorPackage() {
  return {
    assignedDoctorUid: 'doctor-1',
    patient: {
      fullName: 'Meera Kumar',
      phone: '9999999999',
      dateOfBirth: '1978-02-12',
      pinCode: '625106',
      village: 'Melur',
      state: 'Tamil Nadu',
      district: 'Madurai',
    },
    clinical: {
      patientHash: 'patient-hash',
      ageBand: '45-54',
      pinPrefix: '625',
      villageCode: 'melur-code',
    },
    assessment: {
      visitId: 'visit-1',
      patientHash: 'patient-hash',
      carePlan: {
        action: 'see_doctor_free',
        doctorBrief: 'Review needed.',
      },
    },
    consent: consent(['doctorShare']),
  };
}

function consent(scopes) {
  return {
    visitId: 'visit-1',
    patientHash: 'patient-hash',
    scopes,
    recordedAt: '2026-05-03T10:00:00.000Z',
    screeningCompletedAt: '2026-05-03T09:00:00.000Z',
    policyVersion: '2026-05',
  };
}
