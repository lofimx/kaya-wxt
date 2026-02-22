use savebutton_daemon::parse_server_file_listing;

#[test]
fn test_parse_server_file_listing_preserves_url_encoding() {
    let body = "2025-01-01T120000-India%20Income%20Tax.pdf\n\
                 2026-02-04T021925-AES%20-%20Cessation.pdf\n\
                 2026-01-27T171207-www-deobald-ca.url\n";

    let files = parse_server_file_listing(body);

    // URL-encoded filenames must be preserved as-is
    assert!(
        files.contains("2025-01-01T120000-India%20Income%20Tax.pdf"),
        "URL-encoded filename should be preserved, not decoded to spaces"
    );
    assert!(
        files.contains("2026-02-04T021925-AES%20-%20Cessation.pdf"),
        "URL-encoded filename should be preserved, not decoded to spaces"
    );
    // Filenames without encoding should be unaffected
    assert!(files.contains("2026-01-27T171207-www-deobald-ca.url"));

    // Must NOT contain decoded versions with spaces
    assert!(
        !files.contains("2025-01-01T120000-India Income Tax.pdf"),
        "Decoded filename with spaces should not be present"
    );
}

#[test]
fn test_parse_server_file_listing_skips_empty_lines() {
    let body = "file1.url\n\n  \nfile2.url\n";
    let files = parse_server_file_listing(body);
    assert_eq!(files.len(), 2);
    assert!(files.contains("file1.url"));
    assert!(files.contains("file2.url"));
}
