// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;

/// @title IVaultSchemasV1
/// @author The Flap Team
/// @notice Shared struct definitions used by VaultFactory and Vault UI schema methods.
///
/// @dev  ── WHY THIS FILE EXISTS ──────────────────────────────────────────────
///
/// The Flap protocol allows anyone to create new vault factories.  Any
/// contract that implements `VaultFactoryBaseV2` can be used to launch
/// tokens via VaultPortal — no on-chain registration is required.
/// Each factory decodes the opaque `vaultData` bytes in
/// `newVault()` differently, and each vault exposes a unique set of
/// user-facing view and write methods.
///
/// Existing vault types (FlapXVault, SplitVault, SnowBallVault,
/// BlackHoleVault) already have purpose-built UIs.  However, the protocol
/// is designed to be extended — any third-party developer can create a new
/// vault factory and vault implementation without modifying the core
/// contracts or the UI codebase.
///
/// Without a self-describing mechanism, a new vault type would require a
/// custom UI to be built and deployed before users could interact with it.
/// The structs in this file solve this problem by providing an on-chain
/// schema that enables **automatic UI generation for any future vault type**.
///
/// Both `VaultFactoryBaseV2.vaultDataSchema()` and
/// `VaultBaseV2.vaultUISchema()` return structs defined here, allowing a
/// generic UI to render creation forms and vault interaction pages for
/// vault types that did not exist when the UI was built.
///
///
/// ── STRUCT CONSOLIDATION ───────────────────────────────────────────────────
///
/// `FieldDescriptor` is the unified leaf type shared by both the factory
/// schema (`VaultDataSchema.fields`) and the vault UI schema
/// (`VaultMethodSchema.inputs` / `VaultMethodSchema.outputs`).  Keeping one
/// struct avoids duplication and ensures the type system is consistent across
/// the protocol.
///
///
/// ── HOW THE UI USES VaultDataSchema (factory side) ─────────────────────────
///
///   1. UI obtains the factory address (e.g. from the token-launch event
///      or a directory service).
///   2. UI calls factory.vaultDataSchema() → gets VaultDataSchema.
///   3. For each field in schema.fields, UI renders an input:
///        "string"   → text input
///        "address"  → address input (with checksum validation)
///        "uint16"   → number input (0–65535)
///        "uint256"  → big-number input
///        "time"     → date/time picker input (alias for uint256;
///                      value is a Unix timestamp in seconds).
///                      When used in outputs, rendered as a
///                      human-readable time string or countdown clock
///        "bool"     → checkbox
///        "bytes"    → hex input
///        "bytes32"  → hex input (32 bytes)
///      For numeric fields, if field.decimals > 0 the UI multiplies the
///      user's input by 10^decimals before encoding.
///        e.g. decimals=18: user types "1" → encoded value is 1e18
///      If decimals == 0 the raw value is used as-is.
///   4. If schema.isArray == true, UI renders an "Add Item" button for
///      dynamic array entries.
///   5. UI encodes the user input via:
///        If isArray: abi.encode(tuple[])
///        Else:       abi.encode(tuple)
///      using the fieldType values to construct the ABI type string.
///   6. Encoded bytes are passed as `vaultData` in NewTaxTokenWithVaultParams.
///
/// NOTE: The current spec only supports either a single tuple or an array
///       of tuples.
///
///
/// ── HOW THE UI USES VaultUISchema (vault side) ─────────────────────────────
///
///   1. UI calls vault.vaultUISchema() → gets VaultUISchema.
///   2. UI displays schema.vaultType as a badge/header and
///      schema.description as subtitle.
///   3. UI always calls vault.description() and displays the result as a
///      dynamic status banner.
///   4. For each method in schema.methods:
///      a. If method.isWriteMethod == false (VIEW):
///         - If method.inputs is empty: call immediately and display results.
///         - If method.inputs is non-empty: render input fields, add a
///           "Query" button.
///           - If method.isInputArray == true, render an "Add Item" button.
///         - For outputs: use field.decimals to format numeric values
///           (e.g. decimals=18: raw 1.5e18 → display "1.5").
///           For "time" fields, display the raw uint256 value as a
///           human-readable time string or a countdown clock.
///         - Derive the ABI type string from outputs[].fieldType +
///           method.isOutputArray.
///         - Use field.name and field.description as column headers/tooltips.
///      b. If method.isWriteMethod == true (WRITE):
///         - Render a form with inputs from method.inputs.
///         - If method.isInputArray == true, render "Add Item" button.
///         - Each input renders based on fieldType:
///             "address" → address input with checksum validation
///             "uint256" → big-number input
///             "uint128" → number input
///             "time"    → date/time picker input (alias for uint256;
///                          value is a Unix timestamp in seconds)
///             "string"  → text input
///             "bytes"   → hex input
///             "bool"    → checkbox
///         - If field.decimals > 0, the UI multiplies the user's
///           human-readable input by 10^decimals before encoding.
///         - If method.approvals is non-empty, BEFORE sending the write
///           transaction the UI executes each ApproveAction in order:
///             i.   Resolve the token address from approval.tokenType:
///                    "taxToken" → call vault.taxToken()
///                    "lpToken"  → call vault.lpToken()
///                    unknown    → skip (log warning, forward-compatible)
///             ii.  Read the amount from the user's input field named by
///                  approval.amountFieldName (already scaled by decimals).
///             iii. Check current allowance: token.allowance(user, vault).
///                  If already sufficient, skip.
///             iv.  Send token.approve(vault, amount) and wait for
///                  confirmation.
///             v.   Repeat for the next ApproveAction.
///         - After all approvals succeed, send the write transaction.
///         - Add a "Submit" / "Execute" button that sends the transaction.
///         - If method.inputs is empty, just render a single action button.
///   5. All methods are displayed in the order returned by vaultUISchema().
///   6. description() output is polled/refreshed periodically as a live
///      status indicator.

// ──────────────────────────────────────────────────────────────────────────────
//  Shared Struct Definitions
// ──────────────────────────────────────────────────────────────────────────────

/// @notice Describes a single field (parameter, return value, or vault-data component).
///
/// @dev   This is the unified leaf type used in both:
///        - `VaultDataSchema.fields`   (factory → describes vaultData encoding)
///        - `VaultMethodSchema.inputs` / `VaultMethodSchema.outputs`  (vault UI)
///
///        Keeping one struct avoids duplication and ensures the type system is
///        consistent across the protocol.
///
/// @param name        Machine-readable name of the field.
///                    Examples: "xHandle", "recipient", "bps", "user", "amount".
///
/// @param fieldType   Solidity ABI type string for the field.
///                    Examples: "string", "address", "uint16", "uint256", "uint128",
///                    "bool", "bytes", "bytes32".
///                    The special value "time" is an alias for "uint256".
///                    The encoded value is a Unix timestamp in seconds.
///                    For ABI encoding purposes the UI treats "time"
///                    identically to "uint256".
///                    - As an **input**, the UI renders a date/time picker.
///                    - As an **output**, the UI renders the value as a
///                      human-readable time string or a countdown clock.
///                    The UI uses this to decide which input widget to render
///                    and how to ABI-encode/decode the value.
///
/// @param description Human-readable explanation of the field, shown as a
///                    label or tooltip in the UI.
///                    Examples: "The Twitter/X handle of the token creator",
///                    "Recipient wallet address",
///                    "Basis points share (10000 = 100%)".
///
/// @param decimals    Decimal precision hint for numeric fields.
///                    - For **factory encoding** (VaultDataSchema context):
///                      If decimals > 0, the UI multiplies the user's input
///                      by 10^decimals before ABI-encoding.
///                      e.g. decimals=18: user types "1" → encoded as 1e18.
///                      If decimals == 0, the raw value is used as-is.
///                    - For **vault display** (VaultMethodSchema.outputs context):
///                      If decimals > 0, the UI divides the raw on-chain value
///                      by 10^decimals for display.
///                      e.g. decimals=18: raw 1.5e18 → display "1.5".
///                      If decimals == 0, the raw value is displayed.
///                    - For non-numeric fields (string, address, bytes, bool),
///                      this should always be 0.
struct FieldDescriptor {
    string name;
    string fieldType;
    string description;
    uint8 decimals;
}

// ──────────────────────────────────────────────────────────────────────────────
//  Factory-side: VaultDataSchema
// ──────────────────────────────────────────────────────────────────────────────

/// @notice Describes the shape of the `vaultData` bytes expected by a
///         VaultFactory's `newVault()` method.
///
/// @dev   A UI calls `factory.vaultDataSchema()` to discover what fields the
///        factory expects, then renders a form accordingly.
///
///        The current spec supports two shapes:
///          • A single tuple   (`isArray == false`)  – e.g. `(string)`
///          • An array of tuples (`isArray == true`)  – e.g. `(address,uint16)[]`
///
///        If `fields` is empty and `isArray` is false, the factory ignores
///        `vaultData` entirely (e.g. SnowBallFactory).
///
/// @param description  Free-form string explaining what the vault does and
///                     what data is required. Shown to the user in the UI.
///
/// @param fields       Ordered list of field descriptors.  Each entry maps to
///                     one component of the ABI-encoded tuple.
///                     For a factory that requires no user input, return an
///                     empty array.
///
/// @param isArray      If true, `vaultData` is ABI-encoded as `tuple[]`
///                     (an array of the tuple described by `fields`).
///                     If false, `vaultData` is ABI-encoded as a single `tuple`.
struct VaultDataSchema {
    string description;
    FieldDescriptor[] fields;
    bool isArray;
}

// ──────────────────────────────────────────────────────────────────────────────
//  Vault-side: VaultUISchema & supporting types
// ──────────────────────────────────────────────────────────────────────────────

/// @notice An ERC-20 `approve` action that the UI must execute **before**
///         calling a write method on the vault.
///
/// @dev   The spender is always the vault contract itself.
///
///        Known `tokenType` values:
///          • "taxToken" – the vault's own tax token (resolved via vault.taxToken())
///          • "lpToken"  – the associated LP token  (resolved via vault.lpToken())
///
///        New token types can be added in the future without changing this
///        struct.  The UI **MUST** ignore any `tokenType` it does not
///        recognise (forward-compatible).
///
///        Workflow for the UI when processing an ApproveAction:
///          1. Resolve the token address from `tokenType`:
///               "taxToken" → call vault.taxToken()
///               "lpToken"  → call vault.lpToken()
///               unknown    → skip with a warning (forward-compatible)
///          2. Read the amount from the user's input field whose `name`
///             matches `amountFieldName`.  The value should already be
///             scaled by the field's `decimals`.
///          3. Check current allowance: token.allowance(user, vault).
///             If already sufficient, skip.
///          4. Send token.approve(vault, amount) and wait for confirmation.
///
/// @param tokenType       Which token to approve.
///                        e.g. "taxToken", "lpToken".
///
/// @param amountFieldName The `name` of the write method's input
///                        FieldDescriptor whose value should be used as
///                        the approve amount.
///                        e.g. "amount".
struct ApproveAction {
    string tokenType;
    string amountFieldName;
}

/// @notice Describes a single view or write method that the UI should render
///         for a vault.
///
/// @dev   The UI iterates over the `methods` array in `VaultUISchema` and
///        renders each method as either a read-only query panel (view) or an
///        interactive form (write).
///
/// @param name          Solidity method name.
///                      e.g. "claim", "getRecipientsInfo", "stats",
///                      "dispatch", "transitState", "manageByProof".
///
/// @param description   Human-readable explanation of what the method does.
///                      Shown as a subtitle or tooltip in the UI.
///
/// @param inputs        Ordered list of input parameters.
///                      Empty for no-arg methods (e.g. dispatch(), stats()).
///                      Each FieldDescriptor maps to one method parameter.
///
/// @param outputs       Ordered list of return values.
///                      Empty for write methods (tx receipts don't return data
///                      to the UI).
///                      Each FieldDescriptor maps to one return component.
///                      The UI uses `field.decimals` to format numeric values
///                      for display.
///
/// @param approvals     Ordered list of ERC-20 approve actions the UI must
///                      execute **before** sending the write transaction.
///                      The spender is always the vault contract.
///                      Empty for:
///                        • view methods
///                        • write methods that need no prior approval
///
/// @param isInputArray  If true, the method's input is an array of tuples
///                      described by `inputs`.  The UI should render an
///                      "Add Row" button for dynamic array entries.
///
/// @param isOutputArray If true, the method's return value is an array of
///                      tuples described by `outputs`.  The UI should render
///                      results as a table with one row per element.
///
/// @param isWriteMethod If true, the method is state-changing and the UI
///                      should send a transaction.
///                      If false, the method is a view call and the UI
///                      should display the returned data.
struct VaultMethodSchema {
    string name;
    string description;
    FieldDescriptor[] inputs;
    FieldDescriptor[] outputs;
    ApproveAction[] approvals;
    bool isInputArray;
    bool isOutputArray;
    bool isWriteMethod;
}

/// @notice Top-level schema describing the vault's entire UI surface.
///
/// @dev   Returned by `VaultBaseV2.vaultUISchema()`.  The UI uses this to
///        build the complete vault interaction page.
///
///        Rendering algorithm:
///          1. Display `vaultType` as a badge/header.
///          2. Display `description` as a subtitle.
///          3. Always call `vault.description()` and display the result as a
///             dynamic status banner (polled/refreshed periodically).
///          4. Iterate `methods` and render each one according to its
///             `isWriteMethod` flag (see VaultMethodSchema docs above).
///          5. Methods are displayed in the order returned.
///
/// @param vaultType    Human-readable vault type identifier.
///                     e.g. "FlapXVault", "SplitVault", "SnowBallVault",
///                     "BlackHoleVault".
///
/// @param description  Overall explanation of the vault for the UI.
///                     e.g. "Distributes received BNB among a fixed set of
///                     recipients by basis-point shares."
///
/// @param methods      All methods the UI should render.
///                     Ordered — the UI displays them in this order.
struct VaultUISchema {
    string vaultType;
    string description;
    VaultMethodSchema[] methods;
}
