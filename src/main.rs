use std::env;

fn mask(value: &str) -> String {
    let len = value.len();
    if len <= 4 {
        return "*".repeat(len);
    }
    format!("{}{}",  &value[..2], "*".repeat(len - 2))
}

fn check_secret(name: &str) -> (bool, String) {
    match env::var(name) {
        Ok(val) if !val.is_empty() => (true, mask(&val)),
        Ok(_) => (false, "(empty)".to_string()),
        Err(_) => (false, "(not set)".to_string()),
    }
}

fn main() {
    println!("=== ESO Secret Validator ===");
    println!("Pod: {}", env::var("HOSTNAME").unwrap_or_else(|_| "unknown".to_string()));
    println!();

    let checks = [
        ("DB_PASSWORD", "demo-db-password"),
        ("API_KEY",     "demo-api-key"),
    ];

    let mut all_ok = true;

    for (env_var, kv_key) in &checks {
        let (ok, display) = check_secret(env_var);
        let status = if ok { "OK" } else { "MISSING" };
        println!("[{status}] {env_var} (from AKV key: {kv_key}) = {display}");
        if !ok {
            all_ok = false;
        }
    }

    println!();
    if all_ok {
        println!("All secrets loaded successfully from Azure Key Vault via ESO.");
    } else {
        println!("ERROR: One or more secrets are missing. Check SecretStore/ExternalSecret status.");
        std::process::exit(1);
    }
}
