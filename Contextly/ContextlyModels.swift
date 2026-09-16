import Foundation

struct ContextlyUser: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let username: String
    let displayName: String

    enum CodingKeys: String, CodingKey {
        case id
        case username
        case displayName = "display_name"
    }
}

struct ContextlyMessage: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let conversationId: UUID
    let senderId: UUID
    let content: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case conversationId = "conversation_id"
        case senderId = "sender_id"
        case content
        case createdAt = "created_at"
    }
}

struct SearchResult: Identifiable, Hashable, Sendable {
    let id: UUID
    let message: ContextlyMessage
    let score: Double?
}

struct ConversationSummary: Identifiable, Hashable, Sendable {
    let id: UUID
    let name: String
    let memberIds: [UUID]
}

enum DemoData {
    static let nathan = ContextlyUser(
        id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
        username: "nathan",
        displayName: "Nathan"
    )

    static let kevin = ContextlyUser(
        id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
        username: "kevin",
        displayName: "Kevin"
    )

    static let maya = ContextlyUser(
        id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
        username: "maya",
        displayName: "Maya"
    )

    static let priya = ContextlyUser(
        id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
        username: "priya",
        displayName: "Priya"
    )

    static let leo = ContextlyUser(
        id: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!,
        username: "leo",
        displayName: "Leo"
    )

    static let users = [nathan, kevin, maya, priya, leo]

    static let conversation = ConversationSummary(
        id: UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!,
        name: "Contextly MVP",
        memberIds: [nathan.id, kevin.id, maya.id]
    )

    static let designReview = ConversationSummary(
        id: UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!,
        name: "Design Review",
        memberIds: [nathan.id, priya.id]
    )

    static let aiStudyGroup = ConversationSummary(
        id: UUID(uuidString: "cccccccc-cccc-cccc-cccc-cccccccccccc")!,
        name: "AI Study Group",
        memberIds: [nathan.id, kevin.id, maya.id, priya.id, leo.id]
    )

    static let weekendPlans = ConversationSummary(
        id: UUID(uuidString: "dddddddd-dddd-dddd-dddd-dddddddddddd")!,
        name: "Weekend Plans",
        memberIds: [nathan.id, leo.id]
    )

    static let conversations = [conversation, designReview, aiStudyGroup, weekendPlans]

    static let messagesByConversation: [UUID: [ContextlyMessage]] = [
        conversation.id: [
            ContextlyMessage(
                id: UUID(uuidString: "aaaaaaaa-0000-0000-0000-000000000001")!,
                conversationId: conversation.id,
                senderId: nathan.id,
                content: "Where's the plan for the Supabase MVP?",
                createdAt: Date(timeIntervalSinceNow: -9000)
            ),
            ContextlyMessage(
                id: UUID(uuidString: "aaaaaaaa-0000-0000-0000-000000000002")!,
                conversationId: conversation.id,
                senderId: kevin.id,
                content: "I'll finish the backend before then.",
                createdAt: Date(timeIntervalSinceNow: -7800)
            ),
            ContextlyMessage(
                id: UUID(uuidString: "aaaaaaaa-0000-0000-0000-000000000003")!,
                conversationId: conversation.id,
                senderId: nathan.id,
                content: "Great. Let's meet at Klaus at 5 tomorrow.",
                createdAt: Date(timeIntervalSinceNow: -6500)
            ),
            ContextlyMessage(
                id: UUID(uuidString: "aaaaaaaa-0000-0000-0000-000000000004")!,
                conversationId: conversation.id,
                senderId: maya.id,
                content: "I can work on the database after class.",
                createdAt: Date(timeIntervalSinceNow: -4200)
            ),
            ContextlyMessage(
                id: UUID(uuidString: "aaaaaaaa-0000-0000-0000-000000000005")!,
                conversationId: conversation.id,
                senderId: kevin.id,
                content: "Search should answer natural questions, not just exact keywords.",
                createdAt: Date(timeIntervalSinceNow: -2400)
            ),
            ContextlyMessage(
                id: UUID(uuidString: "aaaaaaaa-0000-0000-0000-000000000006")!,
                conversationId: conversation.id,
                senderId: maya.id,
                content: "Perfect. I'll add embeddings once the schema is ready.",
                createdAt: Date(timeIntervalSinceNow: -900)
            )
        ],
        designReview.id: [
            ContextlyMessage(
                id: UUID(uuidString: "bbbbbbbb-0000-0000-0000-000000000001")!,
                conversationId: designReview.id,
                senderId: priya.id,
                content: "The baby purple icon feels friendlier than the dark one.",
                createdAt: Date(timeIntervalSinceNow: -7000)
            ),
            ContextlyMessage(
                id: UUID(uuidString: "bbbbbbbb-0000-0000-0000-000000000002")!,
                conversationId: designReview.id,
                senderId: nathan.id,
                content: "Agreed. Let's keep the UI mostly white with lavender accents.",
                createdAt: Date(timeIntervalSinceNow: -3600)
            )
        ],
        aiStudyGroup.id: [
            ContextlyMessage(
                id: UUID(uuidString: "cccccccc-0000-0000-0000-000000000001")!,
                conversationId: aiStudyGroup.id,
                senderId: leo.id,
                content: "Can Contextly find who mentioned vector search last week?",
                createdAt: Date(timeIntervalSinceNow: -6200)
            ),
            ContextlyMessage(
                id: UUID(uuidString: "cccccccc-0000-0000-0000-000000000002")!,
                conversationId: aiStudyGroup.id,
                senderId: maya.id,
                content: "Yes, embeddings should make that work without exact keywords.",
                createdAt: Date(timeIntervalSinceNow: -5100)
            ),
            ContextlyMessage(
                id: UUID(uuidString: "cccccccc-0000-0000-0000-000000000003")!,
                conversationId: aiStudyGroup.id,
                senderId: kevin.id,
                content: "I'll demo the AI Search sheet after class.",
                createdAt: Date(timeIntervalSinceNow: -2300)
            )
        ],
        weekendPlans.id: [
            ContextlyMessage(
                id: UUID(uuidString: "dddddddd-0000-0000-0000-000000000001")!,
                conversationId: weekendPlans.id,
                senderId: leo.id,
                content: "Are we still grabbing coffee Saturday morning?",
                createdAt: Date(timeIntervalSinceNow: -8200)
            ),
            ContextlyMessage(
                id: UUID(uuidString: "dddddddd-0000-0000-0000-000000000002")!,
                conversationId: weekendPlans.id,
                senderId: nathan.id,
                content: "Yes, 10 works. Remind me where we picked?",
                createdAt: Date(timeIntervalSinceNow: -3100)
            )
        ]
    ]

    static var messages: [ContextlyMessage] {
        messagesByConversation[conversation.id] ?? []
    }
}
