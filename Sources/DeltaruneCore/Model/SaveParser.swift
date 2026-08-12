import Foundation

/// Walks the fixed positional layout of a save file and records which line index holds
/// which field.
///
/// It deliberately reads no values — the layout depends only on the format and the total
/// line count, so the map can be built from those alone. Values are always read back out
/// of `SaveDocument.lines`, keeping a single source of truth.
public enum SaveParser {
    public struct Mapping: Sendable {
        public let fields: [FieldID: Int]
        public let flagCount: Int
    }

    /// Number of trailing lines after the flag array: plot, room, time.
    static let trailingFieldCount = 3

    public static func map(lineCount: Int, format: SaveFormat) throws -> Mapping {
        var cursor = Cursor(totalLines: lineCount)

        try cursor.take(.playerName)
        try cursor.take(.vesselName)
        try cursor.skip(5)                       // five blank lines, purpose unknown

        for slot in 0..<3 { try cursor.take(.party(slot)) }
        try cursor.take(.money)
        try cursor.take(.xp)
        try cursor.take(.lv)
        try cursor.take(.inv)
        try cursor.take(.invc)
        try cursor.take(.inDarkWorld)

        let statFields = WeaponStatField.ordered(for: format)
        for character in 0..<format.characterCount {
            try cursor.take(.charHealth(character))
            try cursor.take(.charMaxHealth(character))
            try cursor.take(.charAttack(character))
            try cursor.take(.charDefence(character))
            try cursor.take(.charMagic(character))
            try cursor.take(.charGuts(character))
            try cursor.take(.charWeapon(character))
            try cursor.take(.charPrimaryArmor(character))
            try cursor.take(.charSecondaryArmor(character))
            try cursor.take(.charWeaponStyle(character))

            for slot in 0..<4 {
                for field in statFields {
                    try cursor.take(.charWeaponStat(character: character, slot: slot, field: field))
                }
            }

            for index in 0..<12 {
                try cursor.take(.charSpell(character: character, index: index))
            }
        }

        try cursor.take(.battleBoltSpeed)
        try cursor.take(.battleGrazeAmount)
        try cursor.take(.battleGrazeSize)

        switch format {
        case .v1:
            // Four parallel inventories interleaved one entry at a time.
            for index in 0..<13 {
                try cursor.take(.invConsumable(index))
                try cursor.take(.invKeyItem(index))
                try cursor.take(.invWeapon(index))
                try cursor.take(.invArmor(index))
            }
        case .v2:
            for index in 0..<13 {
                try cursor.take(.invConsumable(index))
                try cursor.take(.invKeyItem(index))
            }
            for index in 0..<48 {
                try cursor.take(.invWeapon(index))
                try cursor.take(.invArmor(index))
            }
            for index in 0..<72 {
                try cursor.take(.invStorage(index))
            }
        }

        try cursor.take(.tension)
        try cursor.take(.maxTension)

        try cursor.take(.lightWeapon)
        try cursor.take(.lightArmor)
        try cursor.take(.lightExperience)
        try cursor.take(.lightLevel)
        try cursor.take(.lightMoney)
        try cursor.take(.lightHealth)
        try cursor.take(.lightMaxHealth)
        try cursor.take(.lightAttack)
        try cursor.take(.lightDefence)
        try cursor.take(.lightWeaponStrength)
        try cursor.take(.lightArmorDefence)

        for index in 0..<8 {
            try cursor.take(.lightItem(index))
            try cursor.take(.lightPhone(index))
        }

        // The flag array absorbs whatever is left before the three trailing fields, which
        // is how files with slightly different totals still parse.
        let flagCount = lineCount - cursor.position - trailingFieldCount
        guard flagCount >= format.minimumFlagCount else {
            throw SaveDocumentError.tooFewFlags(
                found: max(flagCount, 0),
                expected: format.minimumFlagCount
            )
        }
        for index in 0..<flagCount { try cursor.take(.flag(index)) }

        try cursor.take(.plot)
        try cursor.take(.room)
        try cursor.take(.time)

        return Mapping(fields: cursor.fields, flagCount: flagCount)
    }

    /// Assigns consecutive line indices to fields, refusing to run off the end of the file.
    private struct Cursor {
        let totalLines: Int
        private(set) var position = 0
        private(set) var fields: [FieldID: Int] = [:]

        init(totalLines: Int) {
            self.totalLines = totalLines
            fields.reserveCapacity(totalLines)
        }

        mutating func take(_ field: FieldID) throws {
            guard position < totalLines else {
                throw SaveDocumentError.truncated(atLine: position + 1)
            }
            fields[field] = position
            position += 1
        }

        mutating func skip(_ count: Int) throws {
            guard position + count <= totalLines else {
                throw SaveDocumentError.truncated(atLine: position + 1)
            }
            position += count
        }
    }
}
