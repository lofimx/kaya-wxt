use std::collections::HashSet;

pub fn parse_server_file_listing(body: &str) -> HashSet<String> {
    body.lines()
        .map(|l| l.trim().to_string())
        .filter(|s| !s.is_empty())
        .collect()
}
