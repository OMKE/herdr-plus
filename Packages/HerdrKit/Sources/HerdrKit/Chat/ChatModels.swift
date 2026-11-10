import Foundation

public struct ToolCall: Sendable, Hashable {
    public var id: String
    public var toolName: String
    public var summary: String
    public var input: String
    public var output: String?
    public var isError: Bool = false

    public var isDone: Bool { output != nil }
}

public struct ToolChip: Sendable, Hashable, Identifiable {
    public var id: String
    public var symbol: String
    public var text: String
    public var calls: [ToolCall]
}

public struct PermissionRequest: Sendable, Hashable {
    public var title: String
    public var command: String
    public var toolName: String
    public var toolUseId: String
}

public struct QuestionRequest: Sendable, Hashable {
    public enum Delivery: String, Sendable, Hashable { case picker, message }

    public enum State: Sendable, Hashable {
        case pending
        case answered([String]?)
        case declined
    }

    public struct Option: Sendable, Hashable {
        public var label: String
        public var detail: String
        public var recommended: Bool

        public init(label: String, detail: String = "", recommended: Bool = false) {
            self.label = label
            self.detail = detail
            self.recommended = recommended
        }
    }

    public struct Question: Sendable, Hashable {
        public var id: String
        public var header: String
        public var text: String
        public var options: [Option]
        public var multiSelect: Bool

        public init(id: String? = nil, header: String, text: String, options: [Option], multiSelect: Bool) {
            self.id = id ?? text
            self.header = header
            self.text = text
            self.options = options
            self.multiSelect = multiSelect
        }
    }

    public var toolUseId: String
    public var agent: String
    public var delivery: Delivery
    public var questions: [Question]
    public var state: State
    public var headers: [String]

    public init(toolUseId: String, agent: String, delivery: Delivery = .picker, questions: [Question], state: State = .pending, headers: [String] = []) {
        self.toolUseId = toolUseId
        self.agent = agent
        self.delivery = delivery
        self.questions = questions
        self.state = state
        self.headers = headers
    }

    public var isFromScreen: Bool { toolUseId.hasPrefix("screen-") }
}

public struct QuestionAnswer: Sendable, Hashable {
    public var picks: [Int]
    public var other: String?

    public init(picks: [Int], other: String? = nil) {
        self.picks = picks
        self.other = other
    }
}

public struct ChatItem: Sendable, Hashable, Identifiable {
    public enum Kind: Sendable, Hashable {
        case user(String)
        case assistant(String)
        case tools([ToolChip])
        case permission(PermissionRequest)
        case question(QuestionRequest)
        case status(String)
    }

    public var id: String
    public var kind: Kind
    public var timestamp: Date?
    public var images: Int = 0
    public var imageKeys: [String] = []
}

public struct ChatRow: Sendable, Hashable, Identifiable {
    public enum Kind: Sendable, Hashable {
        case user(text: String, from: String?)
        case assistant(String)
        case tools([ToolChip])
        case permission(PermissionRequest)
        case question(QuestionRequest)
        case status(String)
        case separator(String)
        case footer(String)
    }

    public var id: String
    public var kind: Kind
    public var timestamp: Date?
    public var images: Int = 0
    public var imageKeys: [String] = []
    public var pending = false

    public init(id: String, kind: Kind, timestamp: Date? = nil, images: Int = 0, imageKeys: [String] = [], pending: Bool = false) {
        self.id = id
        self.kind = kind
        self.timestamp = timestamp
        self.images = images
        self.imageKeys = imageKeys
        self.pending = pending
    }
}

public enum ChatCard: Sendable, Hashable {
    case approval(ApprovalCard)
    case question(QuestionRequest)
    case review(String)
}

public struct ApprovalCard: Sendable, Hashable {
    public var id: String
    public var title: String
    public var tool: String
    public var command: String
    public var clipped: Bool
}
