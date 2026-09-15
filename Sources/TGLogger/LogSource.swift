/// Call-site origin captured from `#fileID`, `#function`, `#line`, and `#column`.
public struct LogSource: Sendable, Equatable, Hashable {
    public let fileID: String
    public let function: String
    public let line: UInt
    public let column: UInt

    public init(fileID: String, function: String, line: UInt, column: UInt) {
        self.fileID = fileID
        self.function = function
        self.line = line
        self.column = column
    }

    /// Last path component of `#fileID` (`Module/File.swift` → `File.swift`).
    public var fileName: String {
        if let slash = fileID.lastIndex(of: "/") {
            return String(fileID[fileID.index(after: slash)...])
        }
        return fileID
    }
}
