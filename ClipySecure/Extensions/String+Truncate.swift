extension String {
    func truncated(to maxLength: Int = Constants.maxTitleLength, trailing: String = "\u{2026}") -> String {
        if count <= maxLength {
            return self
        }
        return String(prefix(maxLength)) + trailing
    }
}
