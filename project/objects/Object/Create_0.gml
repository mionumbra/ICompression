var _tests_passed = run_all_tests();
if (!_tests_passed) {
    // No show_error(): its modal dialog blocks unattended runs (release gate
    // and CI). The printed "Tests: ... failed" summary is the failure signal;
    // release.ps1 requires every summary to report total==passed, failed==0.
    show_debug_message("ICompression test suite FAILED");
}
game_end();
