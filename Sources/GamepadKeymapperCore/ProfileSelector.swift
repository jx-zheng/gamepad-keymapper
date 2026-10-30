import Foundation

enum ProfileSelector {
    /// Picks the profile that should receive controller input.
    ///
    /// A pinned override wins. Otherwise the first enabled profile whose bundle id list
    /// contains the frontmost app wins. Otherwise the default profile, then any enabled profile.
    static func select(
        from profiles: [Profile],
        frontmostBundleID: String?,
        overrideID: UUID?
    ) -> Profile? {
        let enabled = profiles.filter(\.enabled)
        if let overrideID, let pinned = enabled.first(where: { $0.id == overrideID }) {
            return pinned
        }
        if let frontmostBundleID {
            let needle = frontmostBundleID.lowercased()
            if let match = enabled.first(where: { profile in
                profile.bundleIdentifiers.contains { $0.lowercased() == needle }
            }) {
                return match
            }
        }
        return enabled.first(where: \.isDefault) ?? enabled.first
    }
}
