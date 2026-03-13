use std::path::PathBuf;

pub fn socket_path() -> String {
    let uid = unsafe { libc::getuid() };
    format!("/tmp/parallax-{uid}.sock")
}

pub fn data_dir() -> PathBuf {
    let home = std::env::var("HOME").unwrap_or_else(|_| "/tmp".into());
    PathBuf::from(home).join(".local/share/parallax")
}

pub fn db_path() -> PathBuf {
    data_dir().join("parallax.db")
}

pub fn global_prescript_path() -> PathBuf {
    let home = std::env::var("HOME").unwrap_or_else(|_| "/tmp".into());
    PathBuf::from(home).join(".config/parallax/prescript.sh")
}
