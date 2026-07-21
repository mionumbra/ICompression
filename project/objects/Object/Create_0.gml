var _tests_passed = run_all_tests();
if (!_tests_passed) {
    show_error("ICompression test suite failed", true);
}
game_end();
