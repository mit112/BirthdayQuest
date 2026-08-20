export default {
  test: {
    environment: 'node',
    testTimeout: 20000,
    hookTimeout: 20000,
    // Both rules test files share the emulator project (birthdayquest-test) and call
    // clearFirestore() in beforeEach. vitest parallelises test FILES by default, which lets
    // them clobber each other's seed data non-deterministically. Force serial file execution.
    fileParallelism: false,
  },
};
