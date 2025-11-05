use claimdrop_contract::helpers::{validate_raw_address, MAX_PLACEHOLDER_ADDRESS_LEN};
use cosmwasm_std::testing::mock_dependencies;
use mantra_claimdrop_std::error::ContractError;

#[test]
fn valid_bech32_address() {
    let deps = mock_dependencies();
    let address_raw = "cosmos1AABBccddeeffgghhii001122334455667789";
    let result = validate_raw_address(deps.as_ref(), address_raw);
    assert!(result.is_ok());
    assert_eq!(result.unwrap(), address_raw.to_lowercase());
}

#[test]
fn invalid_bech32_but_valid_placeholder() {
    let deps = mock_dependencies();
    let address_raw = "example.eth";
    let result = validate_raw_address(deps.as_ref(), address_raw);
    assert!(result.is_ok());
    assert_eq!(result.unwrap(), "example.eth");
}

#[test]
fn invalid_bech32_and_invalid_placeholder() {
    let deps = mock_dependencies();
    let address_raw = "invalid\x01address"; // control character (should fail)
    let result = validate_raw_address(deps.as_ref(), address_raw);
    assert!(matches!(result, Err(ContractError::InvalidInput { .. })));
}

#[test]
fn uppercase_bech32_address() {
    let deps = mock_dependencies();
    let address_raw = "Cosmos1aabbccddeeffgghhii001122334455667789";
    let result = validate_raw_address(deps.as_ref(), address_raw);
    assert!(result.is_ok());
    assert_eq!(result.unwrap(), address_raw.to_lowercase());
}

#[test]
fn empty_string() {
    let deps = mock_dependencies();
    let address_raw = "";
    let result = validate_raw_address(deps.as_ref(), address_raw);
    assert!(matches!(result, Err(ContractError::InvalidInput { .. })));
}

#[test]
fn placeholder_too_long() {
    let deps = mock_dependencies();
    let placeholder = "a".repeat(MAX_PLACEHOLDER_ADDRESS_LEN + 1);
    let result = validate_raw_address(deps.as_ref(), &placeholder);
    assert!(matches!(result, Err(ContractError::InvalidInput { .. })));
}

#[test]
fn placeholder_with_control_chars() {
    let deps = mock_dependencies();
    let address_raw = "invalid\x00address"; // null character (control char)
    let result = validate_raw_address(deps.as_ref(), address_raw);
    assert!(matches!(result, Err(ContractError::InvalidInput { .. })));
}

// ENS Domain Tests
#[test]
fn ens_basic_domain() {
    let deps = mock_dependencies();
    let address_raw = "example.eth";
    let result = validate_raw_address(deps.as_ref(), address_raw);
    assert!(result.is_ok());
    assert_eq!(result.unwrap(), "example.eth");
}

#[test]
fn ens_subdomain() {
    let deps = mock_dependencies();
    let address_raw = "sub.domain.eth";
    let result = validate_raw_address(deps.as_ref(), address_raw);
    assert!(result.is_ok());
    assert_eq!(result.unwrap(), "sub.domain.eth");
}

#[test]
fn ens_emoji_single() {
    let deps = mock_dependencies();
    let address_raw = "🌮.eth";
    let result = validate_raw_address(deps.as_ref(), address_raw);
    assert!(result.is_ok());
    assert_eq!(result.unwrap(), "🌮.eth");
}

#[test]
fn ens_emoji_multiple() {
    let deps = mock_dependencies();
    let address_raw = "👁👄👁.eth";
    let result = validate_raw_address(deps.as_ref(), address_raw);
    assert!(result.is_ok());
    assert_eq!(result.unwrap(), "👁👄👁.eth");
}

#[test]
fn ens_emoji_sequence() {
    let deps = mock_dependencies();
    let address_raw = "🌑🌒🌓🌔🌕.eth";
    let result = validate_raw_address(deps.as_ref(), address_raw);
    assert!(result.is_ok());
    assert_eq!(result.unwrap(), "🌑🌒🌓🌔🌕.eth");
}

#[test]
fn ens_international_latin_accents() {
    let deps = mock_dependencies();
    let address_raw = "café.eth";
    let result = validate_raw_address(deps.as_ref(), address_raw);
    assert!(result.is_ok());
    assert_eq!(result.unwrap(), "café.eth");
}

#[test]
fn ens_cyrillic() {
    let deps = mock_dependencies();
    let address_raw = "привет.eth";
    let result = validate_raw_address(deps.as_ref(), address_raw);
    assert!(result.is_ok());
    assert_eq!(result.unwrap(), "привет.eth");
}

#[test]
fn ens_chinese() {
    let deps = mock_dependencies();
    let address_raw = "中文.eth";
    let result = validate_raw_address(deps.as_ref(), address_raw);
    assert!(result.is_ok());
    assert_eq!(result.unwrap(), "中文.eth");
}

#[test]
fn ens_japanese() {
    let deps = mock_dependencies();
    let address_raw = "日本語.eth";
    let result = validate_raw_address(deps.as_ref(), address_raw);
    assert!(result.is_ok());
    assert_eq!(result.unwrap(), "日本語.eth");
}

#[test]
fn ens_korean() {
    let deps = mock_dependencies();
    let address_raw = "한국어.eth";
    let result = validate_raw_address(deps.as_ref(), address_raw);
    assert!(result.is_ok());
    assert_eq!(result.unwrap(), "한국어.eth");
}

#[test]
fn ens_bitcoin_symbol() {
    let deps = mock_dependencies();
    let address_raw = "₿itcoin.eth";
    let result = validate_raw_address(deps.as_ref(), address_raw);
    assert!(result.is_ok());
    assert_eq!(result.unwrap(), "₿itcoin.eth");
}

#[test]
fn ens_with_hyphens() {
    let deps = mock_dependencies();
    let address_raw = "test-domain.eth";
    let result = validate_raw_address(deps.as_ref(), address_raw);
    assert!(result.is_ok());
    assert_eq!(result.unwrap(), "test-domain.eth");
}

#[test]
fn ens_with_underscores() {
    let deps = mock_dependencies();
    let address_raw = "test_domain.eth";
    let result = validate_raw_address(deps.as_ref(), address_raw);
    assert!(result.is_ok());
    assert_eq!(result.unwrap(), "test_domain.eth");
}

// Other Placeholder Types
#[test]
fn email_like_placeholder() {
    let deps = mock_dependencies();
    let address_raw = "user@example.com";
    let result = validate_raw_address(deps.as_ref(), address_raw);
    assert!(result.is_ok());
    assert_eq!(result.unwrap(), "user@example.com");
}

#[test]
fn social_handle_at() {
    let deps = mock_dependencies();
    let address_raw = "@username";
    let result = validate_raw_address(deps.as_ref(), address_raw);
    assert!(result.is_ok());
    assert_eq!(result.unwrap(), "@username");
}

#[test]
fn social_handle_hash() {
    let deps = mock_dependencies();
    let address_raw = "#hashtag";
    let result = validate_raw_address(deps.as_ref(), address_raw);
    assert!(result.is_ok());
    assert_eq!(result.unwrap(), "#hashtag");
}

#[test]
fn mixed_symbols_and_numbers() {
    let deps = mock_dependencies();
    let address_raw = "user-123_test!@#$%";
    let result = validate_raw_address(deps.as_ref(), address_raw);
    assert!(result.is_ok());
    assert_eq!(result.unwrap(), "user-123_test!@#$%");
}

#[test]
fn special_unicode_symbols() {
    let deps = mock_dependencies();
    let address_raw = "★☆♠♥♦♣♪♫";
    let result = validate_raw_address(deps.as_ref(), address_raw);
    assert!(result.is_ok());
    assert_eq!(result.unwrap(), "★☆♠♥♦♣♪♫");
}

// Ethereum Address Tests
#[test]
fn ethereum_address_lowercase() {
    let deps = mock_dependencies();
    let address_raw = "0x742d35cc6361c4c93f09bb9eca5e90de2c0a5b8f";
    let result = validate_raw_address(deps.as_ref(), address_raw);
    assert!(result.is_ok());
    assert_eq!(
        result.unwrap(),
        "0x742d35cc6361c4c93f09bb9eca5e90de2c0a5b8f"
    );
}

#[test]
fn ethereum_address_mixed_case() {
    let deps = mock_dependencies();
    let address_raw = "0x742d35Cc6361c4c93f09bB9eca5e90de2c0a5B8F";
    let result = validate_raw_address(deps.as_ref(), address_raw);
    assert!(result.is_ok());
    assert_eq!(
        result.unwrap(),
        "0x742d35cc6361c4c93f09bb9eca5e90de2c0a5b8f"
    );
}
