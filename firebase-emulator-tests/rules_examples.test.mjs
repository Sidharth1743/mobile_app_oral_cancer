import assert from 'node:assert/strict';
import { after, afterEach, before, describe, it } from 'node:test';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import { doc, getDoc, setDoc } from 'firebase/firestore';
import { ref, uploadBytes } from 'firebase/storage';

const projectId = 'oral-cancer-e8a6e';
let testEnv;

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId,
    firestore: {
      rules: await readText('firestore.rules'),
    },
    storage: {
      rules: await readText('storage.rules'),
      host: 'localhost',
      port: 9199,
    },
  });
});

afterEach(async () => {
  await testEnv.clearFirestore();
  await testEnv.clearStorage();
});

after(async () => {
  await testEnv.cleanup();
});

describe('Firebase rules examples', () => {
  it('allows ASHA to read private identity for her own case', async () => {
    await seedUser('asha-1', {
      uid: 'asha-1',
      role: 'asha',
      active: true,
      displayName: 'ASHA Worker',
    });
    await seedCase('case-1', {
      caseId: 'case-1',
      visitId: 'visit-1',
      patientHash: 'patient-hash',
      createdByUid: 'asha-1',
      assignedDoctorUid: 'doctor-1',
      riskLevel: 'high',
      recommendedAction: 'see_doctor_free',
    });
    await seedPrivateIdentity('case-1', {
      fullName: 'Meera Kumar',
      phone: '9999999999',
      dateOfBirth: '1978-02-12',
      pinCode: '625106',
      state: 'Tamil Nadu',
      district: 'Madurai',
      village: 'Melur',
      consentId: 'consent-1',
    });

    const asha = testEnv.authenticatedContext('asha-1');
    const snapshot = await assertSucceeds(
      getDoc(doc(asha.firestore(), 'cases/case-1/private/patientIdentity')),
    );

    assert.equal(snapshot.data().fullName, 'Meera Kumar');
  });

  it('denies NGO/CSR access to private patient identity', async () => {
    await seedUser('ngo-1', {
      uid: 'ngo-1',
      role: 'ngo_csr',
      active: true,
      displayName: 'NGO User',
    });
    await seedCase('case-1', {
      caseId: 'case-1',
      visitId: 'visit-1',
      patientHash: 'patient-hash',
      createdByUid: 'asha-1',
      assignedDoctorUid: 'doctor-1',
      riskLevel: 'high',
      recommendedAction: 'see_doctor_free',
    });
    await seedPrivateIdentity('case-1', {
      fullName: 'Meera Kumar',
      phone: '9999999999',
      dateOfBirth: '1978-02-12',
      pinCode: '625106',
      state: 'Tamil Nadu',
      district: 'Madurai',
      village: 'Melur',
      consentId: 'consent-1',
    });

    const ngo = testEnv.authenticatedContext('ngo-1');

    await assertFails(
      getDoc(doc(ngo.firestore(), 'cases/case-1/private/patientIdentity')),
    );
  });

  it('denies raw video upload to Cloud Storage', async () => {
    await seedUser('asha-1', {
      uid: 'asha-1',
      role: 'asha',
      active: true,
      displayName: 'ASHA Worker',
    });
    await seedCase('case-1', {
      caseId: 'case-1',
      visitId: 'visit-1',
      patientHash: 'patient-hash',
      createdByUid: 'asha-1',
      assignedDoctorUid: 'doctor-1',
      riskLevel: 'high',
      recommendedAction: 'see_doctor_free',
    });

    const asha = testEnv.authenticatedContext('asha-1');
    const rawVideo = ref(
      asha.storage(),
      'cases/case-1/visit-1/raw/left_buccal.mp4',
    );

    await assertFails(
      uploadBytes(rawVideo, new Uint8Array([0, 1, 2]), {
        contentType: 'video/mp4',
      }),
    );
  });

  it('allows assigned doctor and denies unassigned doctor private identity reads', async () => {
    await seedUser('doctor-1', {
      uid: 'doctor-1',
      role: 'doctor',
      active: true,
      displayName: 'Assigned Doctor',
    });
    await seedUser('doctor-2', {
      uid: 'doctor-2',
      role: 'doctor',
      active: true,
      displayName: 'Other Doctor',
    });
    await seedCase('case-1', {
      caseId: 'case-1',
      visitId: 'visit-1',
      patientHash: 'patient-hash',
      createdByUid: 'asha-1',
      assignedDoctorUid: 'doctor-1',
      riskLevel: 'high',
      recommendedAction: 'see_doctor_free',
    });
    await seedPrivateIdentity('case-1', {
      fullName: 'Meera Kumar',
      phone: '9999999999',
      dateOfBirth: '1978-02-12',
      pinCode: '625106',
      state: 'Tamil Nadu',
      district: 'Madurai',
      village: 'Melur',
      consentId: 'consent-1',
    });

    const assignedDoctor = testEnv.authenticatedContext('doctor-1');
    const unassignedDoctor = testEnv.authenticatedContext('doctor-2');

    await assertSucceeds(
      getDoc(
        doc(
          assignedDoctor.firestore(),
          'cases/case-1/private/patientIdentity',
        ),
      ),
    );
    await assertFails(
      getDoc(
        doc(
          unassignedDoctor.firestore(),
          'cases/case-1/private/patientIdentity',
        ),
      ),
    );
  });

  it('allows ASHA ROI JPEG upload and denies wrong content type', async () => {
    await seedUser('asha-1', {
      uid: 'asha-1',
      role: 'asha',
      active: true,
      displayName: 'ASHA Worker',
    });
    await seedCase('case-1', {
      caseId: 'case-1',
      visitId: 'visit-1',
      patientHash: 'patient-hash',
      createdByUid: 'asha-1',
      assignedDoctorUid: 'doctor-1',
      riskLevel: 'high',
      recommendedAction: 'see_doctor_free',
    });

    const asha = testEnv.authenticatedContext('asha-1');
    const jpegRoi = ref(asha.storage(), 'cases/case-1/visit-1/roi/left.jpg');
    const pngRoi = ref(asha.storage(), 'cases/case-1/visit-1/roi/wrong.png');

    await assertSucceeds(
      uploadBytes(jpegRoi, new Uint8Array([255, 216, 255]), {
        contentType: 'image/jpeg',
      }),
    );
    await assertFails(
      uploadBytes(pngRoi, new Uint8Array([137, 80, 78, 71]), {
        contentType: 'image/png',
      }),
    );
  });

  it('rejects direct identity fields in public case metadata', async () => {
    await seedUser('asha-1', {
      uid: 'asha-1',
      role: 'asha',
      active: true,
      displayName: 'ASHA Worker',
    });

    const asha = testEnv.authenticatedContext('asha-1');

    await assertFails(
      setDoc(doc(asha.firestore(), 'cases/case-pii'), {
        caseId: 'case-pii',
        visitId: 'visit-1',
        patientHash: 'patient-hash',
        createdByUid: 'asha-1',
        assignedDoctorUid: 'doctor-1',
        riskLevel: 'high',
        recommendedAction: 'see_doctor_free',
        phone: '9999999999',
      }),
    );
    await assertFails(
      setDoc(doc(asha.firestore(), 'cases/case-name'), {
        caseId: 'case-name',
        visitId: 'visit-1',
        patientHash: 'patient-hash',
        createdByUid: 'asha-1',
        assignedDoctorUid: 'doctor-1',
        riskLevel: 'high',
        recommendedAction: 'see_doctor_free',
        fullName: 'Meera Kumar',
      }),
    );
  });

  it('allows assigned doctor to create treatment event', async () => {
    await seedUser('doctor-1', {
      uid: 'doctor-1',
      role: 'doctor',
      active: true,
      displayName: 'Assigned Doctor',
    });
    await seedCase('case-1', {
      caseId: 'case-1',
      visitId: 'visit-1',
      patientHash: 'patient-hash',
      createdByUid: 'asha-1',
      assignedDoctorUid: 'doctor-1',
      riskLevel: 'high',
      recommendedAction: 'see_doctor_free',
    });

    const doctor = testEnv.authenticatedContext('doctor-1');

    await assertSucceeds(
      setDoc(doc(doctor.firestore(), 'cases/case-1/treatment/event-1'), {
        status: 'completed',
        recordedAt: '2026-06-01T00:00:00.000Z',
        actorUid: 'doctor-1',
        note: 'Completed.',
      }),
    );
  });
});

async function seedUser(uid, data) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), `users/${uid}`), data);
  });
}

async function seedCase(caseId, data) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), `cases/${caseId}`), data);
  });
}

async function seedPrivateIdentity(caseId, data) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await setDoc(
      doc(context.firestore(), `cases/${caseId}/private/patientIdentity`),
      data,
    );
  });
}

async function readText(path) {
  const { readFile } = await import('node:fs/promises');
  return readFile(path, 'utf8');
}
