/// Shared by practice and recording. Always starts on 5 or 1 and provides
/// at least three beats before landing on the target count.
nonisolated enum CountOffSequence {
    static func counts(before target: Int) -> [Int] {
        let end = target == 1 ? 8 : target - 1
        func length(from start: Int) -> Int { ((end - start + 8) % 8) + 1 }
        let candidates = [5, 1]
            .map { (start: $0, length: length(from: $0)) }
            .filter { $0.length >= 3 }
        let chosen = candidates.min { $0.length < $1.length }
            ?? (start: 5, length: length(from: 5))
        return (0..<chosen.length).map { ((chosen.start - 1 + $0) % 8) + 1 }
    }
}
