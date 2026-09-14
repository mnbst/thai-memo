const mockDocuments = new Map<string, Record<string, unknown>>();
const mockCommit = jest.fn();
const mockDoc = (path: string) => ({
  path,
  get: async () => ({data: () => mockDocuments.get(path)}),
});
const mockDb = {
  doc: mockDoc,
  collection: (path: string) => ({
    listDocuments: async () => [...mockDocuments.keys()]
      .filter((key) => key.startsWith(`${path}/`) && key.split('/').length === path.split('/').length + 1)
      .map(mockDoc),
    where: (field: string, _op: string, value: unknown) => ({
      get: async () => ({docs: [...mockDocuments.entries()]
        .filter(([key, data]) => key.startsWith(`${path}/`) && data[field] === value)
        .map(([key]) => ({ref: mockDoc(key)}))}),
    }),
  }),
  batch: () => {
    const paths: string[] = [];
    return {
      delete: (ref: {path: string}) => paths.push(ref.path),
      commit: async () => {
        await mockCommit(paths);
        paths.forEach((path) => mockDocuments.delete(path));
      },
    };
  },
};

jest.mock('firebase-admin', () => ({firestore: () => mockDb}));
jest.mock('firebase-functions/v1', () => ({
  region: () => ({auth: {user: () => ({onDelete: (fn: unknown) => fn})}}),
}));

import {deleteUserFirestoreData} from '../deleteUserData';

beforeEach(() => {
  mockDocuments.clear();
  mockCommit.mockReset();
});

test('関連データを全削除し、他ユーザーは保持する。再実行も安全', async () => {
  const owned = [
    'users/u', 'users/u/sentences/s', 'users/u/quiz_answers/q', 'users/u/uvm/w',
    'users/u/learning_state/daily_sets', 'users/u/generation_locks/generate',
    'contact_rate_limits/u', 'quiz_queue/q', 'subscription_owners/purchase',
  ];
  owned.forEach((path) => mockDocuments.set(path, {uid: 'u'}));
  mockDocuments.set('leaderboard/u', {nickname: 'TestName'});
  mockDocuments.set('nicknames/testname', {uid: 'u'});
  mockDocuments.set('users/other', {uid: 'other'});
  mockDocuments.set('subscription_owners/other', {uid: 'other'});
  await deleteUserFirestoreData('u');
  expect([...mockDocuments.keys()].sort()).toEqual(['subscription_owners/other', 'users/other']);
  await expect(deleteUserFirestoreData('u')).resolves.toBeGreaterThan(0);
});

test('500件ずつ削除し、コミット失敗は呼び出し元へ返す', async () => {
  for (let i = 0; i < 501; i++) mockDocuments.set(`users/u/sentences/${i}`, {});
  await deleteUserFirestoreData('u');
  expect(mockCommit.mock.calls.map(([paths]) => paths.length)).toEqual([500, 4]);
  mockCommit.mockRejectedValueOnce(new Error('unavailable'));
  await expect(deleteUserFirestoreData('u')).rejects.toThrow('unavailable');
});
