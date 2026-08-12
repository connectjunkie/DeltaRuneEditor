import Foundation

/// Sensible bounds for the values the simple UI exposes.
///
/// Two reasons these exist. The obvious one is that a nine-year-old will try typing a
/// screenful of nines to see what happens, and the game does not necessarily survive it.
/// The subtler one is that keeping every value under a million avoids GameMaker's
/// exponential notation entirely, so the simple UI only ever writes plain integers.
public enum EditPolicy {

    /// Highest value the simple UI will write. One below the point where the game switches
    /// to exponential form.
    public static let safeMaximum = 999_999

    public static let money = 0...safeMaximum
    public static let health = 0...9_999
    public static let maxHealth = 1...9_999
    public static let stat = 0...999
    public static let level = 1...99
    public static let experience = 0...safeMaximum
    public static let itemID = 0...998          // 999 is the end-of-list marker
    public static let characterID = 0...4

    /// The range a field is held to in the simple UI, or `nil` if it isn't offered there.
    public static func range(for field: FieldID) -> ClosedRange<Int>? {
        switch field {
        case .money, .lightMoney: money
        case .lv, .lightLevel: level
        case .xp, .lightExperience: experience
        case .charHealth, .lightHealth: health
        case .charMaxHealth, .lightMaxHealth: maxHealth
        case .charAttack, .charDefence, .charMagic, .charGuts,
             .lightAttack, .lightDefence: stat
        case .charWeapon, .charPrimaryArmor, .charSecondaryArmor,
             .invConsumable, .invKeyItem, .invWeapon, .invArmor, .invStorage: itemID
        case .party: characterID
        default: nil
        }
    }

    /// Bring a value inside its field's range. Fields with no range are returned unchanged.
    public static func clamp(_ value: Int, for field: FieldID) -> Int {
        guard let range = range(for: field) else { return value }
        return min(max(value, range.lowerBound), range.upperBound)
    }
}

extension SaveDocument {
    /// Set a value, held inside the safe range for that field.
    ///
    /// This is what the simple screens call. `set(_:to:)` stays unrestricted for the
    /// Advanced tab, where the person editing has explicitly asked for the sharp edges.
    public mutating func setClamped(_ field: FieldID, to value: Int) throws {
        try set(field, to: EditPolicy.clamp(value, for: field))
    }

    /// Keep current HP from exceeding max HP, which the game displays oddly.
    public mutating func setMaxHealth(_ character: Int, to value: Int) throws {
        let clamped = EditPolicy.clamp(value, for: .charMaxHealth(character))
        try set(.charMaxHealth(character), to: clamped)

        if let current = int(.charHealth(character)), current > clamped {
            try set(.charHealth(character), to: clamped)
        }
    }

    /// Fill a character's HP to their maximum — the single most requested button.
    public mutating func healToFull(_ character: Int) throws {
        guard let maximum = int(.charMaxHealth(character)) else { return }
        try set(.charHealth(character), to: maximum)
    }
}
