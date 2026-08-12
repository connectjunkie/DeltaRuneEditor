import Foundation

/// One addressable value in a save file.
///
/// A `FieldID` is never a value — it's a *name* for a position. The parser maps each one
/// to a line index, and every read and write goes through that map. Nothing in the app
/// can touch a line that has no `FieldID` pointing at it.
public enum FieldID: Hashable, Sendable {
    // Header
    case playerName
    case vesselName
    case party(Int)             // 0..<3
    case money
    case xp
    case lv
    case inv
    case invc
    case inDarkWorld

    // Per-character stat block
    case charHealth(Int)
    case charMaxHealth(Int)
    case charAttack(Int)
    case charDefence(Int)
    case charMagic(Int)
    case charGuts(Int)
    case charWeapon(Int)
    case charPrimaryArmor(Int)
    case charSecondaryArmor(Int)
    case charWeaponStyle(Int)
    case charWeaponStat(character: Int, slot: Int, field: WeaponStatField)
    case charSpell(character: Int, index: Int)

    // Battle globals
    case battleBoltSpeed
    case battleGrazeAmount
    case battleGrazeSize
    case tension
    case maxTension

    // Inventory
    case invConsumable(Int)
    case invKeyItem(Int)
    case invWeapon(Int)
    case invArmor(Int)
    case invStorage(Int)        // V2 only

    // Light World
    case lightWeapon
    case lightArmor
    case lightExperience
    case lightLevel
    case lightMoney
    case lightHealth
    case lightMaxHealth
    case lightAttack
    case lightDefence
    case lightWeaponStrength
    case lightArmorDefence
    case lightItem(Int)
    case lightPhone(Int)

    // Tail
    case flag(Int)
    case plot
    case room
    case time
}

/// Fields within one weapon-stat entry. `element` and `elementAmount` are V2 only.
public enum WeaponStatField: String, Hashable, Sendable, CaseIterable {
    case attack
    case defence
    case magic
    case bolts
    case grazeAmount
    case grazeSize
    case boltSpeed
    case special
    case element
    case elementAmount

    /// The subset present in a given layout, in file order.
    static func ordered(for format: SaveFormat) -> [WeaponStatField] {
        Array(allCases.prefix(format.weaponStatFieldCount))
    }
}

extension FieldID {
    /// True for fields the simple UI is allowed to edit. Everything else is Advanced-only.
    public var isSimpleEditable: Bool {
        switch self {
        case .money, .lv, .xp,
             .charHealth, .charMaxHealth, .charAttack, .charDefence, .charMagic,
             .charWeapon, .charPrimaryArmor, .charSecondaryArmor,
             .party, .invConsumable, .invKeyItem, .invWeapon, .invArmor, .invStorage,
             .lightMoney, .lightHealth, .lightMaxHealth:
            true
        default:
            false
        }
    }
}
