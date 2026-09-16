import Observation
import SwiftUI

struct ContentView: View {
    @AppStorage("supabaseProjectURL") private var supabaseProjectURL = ""
    @AppStorage("supabasePublishableKey") private var supabasePublishableKey = ""

    @State private var viewModel = ContextlyViewModel()
    @State private var draftMessage = ""
    @State private var isShowingSearch = false
    @State private var isShowingSettings = false
    @State private var isShowingChatList = false

    private var configuration: SupabaseConfiguration {
        SupabaseConfiguration(projectURL: supabaseProjectURL, publishableKey: supabasePublishableKey)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                messages
                composer
            }
            .background(Theme.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .task { await viewModel.load(configuration: configuration) }
            .onChange(of: configuration) { _, value in
                Task { await viewModel.load(configuration: value) }
            }
            .sheet(isPresented: $isShowingChatList) {
                ChatListView(viewModel: viewModel)
            }
            .sheet(isPresented: $isShowingSearch) {
                SearchView(viewModel: viewModel)
            }
            .sheet(isPresented: $isShowingSettings) {
                SettingsView(projectURL: $supabaseProjectURL, publishableKey: $supabasePublishableKey)
            }
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Button {
                    isShowingChatList = true
                } label: {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)

                AvatarView(name: viewModel.conversation.name, size: 42, tint: Theme.purple)

                VStack(alignment: .leading, spacing: 3) {
                    Text(viewModel.conversation.name)
                        .font(.system(size: 18, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                    HStack(spacing: 5) {
                        Circle()
                            .fill(viewModel.isConfigured ? .green : .orange)
                            .frame(width: 7, height: 7)
                        Text(viewModel.connectionLabel)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .layoutPriority(1)

                Spacer(minLength: 4)

                HeaderButton(systemName: "sparkle.magnifyingglass") {
                    isShowingSearch = true
                }
                .disabled(viewModel.messages.isEmpty)

                HeaderButton(systemName: "server.rack") {
                    isShowingSettings = true
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(viewModel.users) { user in
                        UserChip(
                            user: user,
                            isSelected: user.id == viewModel.selectedUserId
                        ) {
                            viewModel.selectedUserId = user.id
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .background(.white)
    }

    private var messages: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 14) {
                    ForEach(viewModel.messages) { message in
                        MessageBubble(
                            message: message,
                            sender: viewModel.user(for: message.senderId),
                            isCurrentUser: message.senderId == viewModel.selectedUserId
                        )
                        .id(message.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 18)
            }
            .refreshable { await viewModel.reload() }
            .onAppear { scrollToLatest(using: proxy) }
            .onChange(of: viewModel.messages) { _, _ in scrollToLatest(using: proxy) }
        }
        .overlay {
            if viewModel.messages.isEmpty && !viewModel.isLoading {
                ContentUnavailableView(
                    "No messages yet",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text("Send the first note and Contextly will keep it searchable.")
                )
            }
        }
    }

    private var composer: some View {
        HStack(spacing: 10) {
            Button {
                isShowingSearch = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(Theme.purple, in: Circle())
            }
            .buttonStyle(.plain)

            HStack(spacing: 8) {
                TextField("Type here", text: $draftMessage, axis: .vertical)
                    .lineLimit(1...3)
                    .font(.system(size: 16))
                    .padding(.vertical, 12)

                Button {
                    sendMessage()
                } label: {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(canSend ? Theme.purple : .secondary.opacity(0.45))
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
            }
            .padding(.leading, 14)
            .padding(.trailing, 8)
            .background(Theme.softGray, in: RoundedRectangle(cornerRadius: 23))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.white)
        .overlay(alignment: .topLeading) {
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.white, in: Capsule())
                    .shadow(color: .black.opacity(0.08), radius: 10, y: 3)
                    .padding(.leading, 18)
                    .offset(y: -34)
            }
        }
    }

    private var canSend: Bool {
        !draftMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && viewModel.selectedUserId != nil
    }

    private func sendMessage() {
        let message = draftMessage
        draftMessage = ""
        Task { await viewModel.send(message) }
    }

    private func scrollToLatest(using proxy: ScrollViewProxy) {
        guard let lastMessage = viewModel.messages.last else { return }
        DispatchQueue.main.async {
            proxy.scrollTo(lastMessage.id, anchor: .bottom)
        }
    }
}

@MainActor
@Observable
final class ContextlyViewModel {
    var users: [ContextlyUser] = DemoData.users
    var conversations: [ConversationSummary] = DemoData.conversations
    var selectedConversation = DemoData.conversation
    var messages: [ContextlyMessage] = DemoData.messages
    var selectedUserId: UUID? = DemoData.nathan.id
    var isLoading = false
    var errorMessage: String?

    var conversation: ConversationSummary { selectedConversation }

    private var configuration = SupabaseConfiguration(projectURL: "", publishableKey: "")
    private var service = SupabaseService(configuration: SupabaseConfiguration(projectURL: "", publishableKey: ""))

    var isConfigured: Bool { configuration.isConfigured }
    var connectionLabel: String { isConfigured ? "Online" : "Demo mode" }

    func load(configuration: SupabaseConfiguration) async {
        self.configuration = configuration
        service = SupabaseService(configuration: configuration)

        guard configuration.isConfigured else {
            users = DemoData.users
            conversations = DemoData.conversations
            messages = DemoData.messagesByConversation[selectedConversation.id] ?? []
            selectedUserId = selectedUserId ?? DemoData.nathan.id
            isLoading = false
            errorMessage = nil
            return
        }

        await reload()
    }

    func reload() async {
        guard configuration.isConfigured else { return }

        isLoading = true
        errorMessage = nil
        do {
            async let fetchedUsers = service.fetchUsers()
            async let fetchedMessages = service.fetchMessages(conversationId: conversation.id)
            users = try await fetchedUsers
            messages = try await fetchedMessages
            if selectedUserId == nil || !users.contains(where: { $0.id == selectedUserId }) {
                selectedUserId = users.first?.id
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func send(_ content: String) async {
        guard let selectedUserId else { return }
        errorMessage = nil
        do {
            let message = try await service.sendMessage(
                conversationId: conversation.id,
                senderId: selectedUserId,
                content: content
            )
            messages.append(message)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func search(_ query: String) async -> [SearchResult] {
        errorMessage = nil
        do {
            return try await service.searchMessages(conversationId: conversation.id, query: query)
        } catch {
            errorMessage = error.localizedDescription
            return []
        }
    }

    func selectConversation(_ conversation: ConversationSummary) async {
        selectedConversation = conversation
        errorMessage = nil

        guard configuration.isConfigured else {
            messages = DemoData.messagesByConversation[conversation.id] ?? []
            return
        }

        isLoading = true
        do {
            messages = try await service.fetchMessages(conversationId: conversation.id)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func user(for id: UUID) -> ContextlyUser? {
        users.first { $0.id == id }
    }

    func lastMessage(for conversation: ConversationSummary) -> ContextlyMessage? {
        if conversation.id == selectedConversation.id {
            return messages.last
        }
        return DemoData.messagesByConversation[conversation.id]?.last
    }

    func members(for conversation: ConversationSummary) -> [ContextlyUser] {
        conversation.memberIds.compactMap { user(for: $0) }
    }
}

private struct ChatListView: View {
    let viewModel: ContextlyViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    storyRow

                    HStack {
                        Text("Chats")
                            .font(.system(size: 22, weight: .bold))
                        Spacer()
                        Image(systemName: "ellipsis")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(Theme.ink)
                    }

                    LazyVStack(spacing: 18) {
                        ForEach(viewModel.conversations) { conversation in
                            ChatRow(
                                conversation: conversation,
                                members: viewModel.members(for: conversation),
                                lastMessage: viewModel.lastMessage(for: conversation),
                                isSelected: conversation.id == viewModel.selectedConversation.id,
                                unreadCount: unreadCount(for: conversation)
                            ) {
                                Task {
                                    await viewModel.selectConversation(conversation)
                                    dismiss()
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 18)
                .padding(.bottom, 28)
            }
            .background(.white)
            .navigationTitle("Contextly")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 18, weight: .semibold))
                }
            }
        }
    }

    private var storyRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 18) {
                VStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.system(size: 24, weight: .medium))
                        .frame(width: 62, height: 62)
                        .background(.white, in: Circle())
                        .overlay(Circle().stroke(Theme.purple.opacity(0.24), style: StrokeStyle(lineWidth: 1.5, dash: [7, 7])))
                    Text("New")
                        .font(.caption)
                }

                ForEach(viewModel.users) { user in
                    VStack(spacing: 8) {
                        AvatarView(name: user.displayName, size: 62, tint: Theme.tint(for: user.id))
                        Text(user.displayName)
                            .font(.caption)
                            .lineLimit(1)
                    }
                    .frame(width: 68)
                }
            }
        }
    }

    private func unreadCount(for conversation: ConversationSummary) -> Int {
        conversation.id == viewModel.selectedConversation.id ? 0 : conversation.memberIds.count == 2 ? 1 : 2
    }
}

private struct ChatRow: View {
    let conversation: ConversationSummary
    let members: [ContextlyUser]
    let lastMessage: ContextlyMessage?
    let isSelected: Bool
    let unreadCount: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                AvatarView(name: conversation.name, size: 56, tint: isSelected ? Theme.purple : Theme.tint(for: conversation.id))

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(conversation.name)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(Theme.ink)
                            .lineLimit(1)
                        if members.count > 2 {
                            Text("\(members.count)")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Theme.purple, in: Capsule())
                        }
                    }

                    Text(previewText)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 8) {
                    if let lastMessage {
                        Text(lastMessage.createdAt, style: .time)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if unreadCount > 0 {
                        Text("\(unreadCount)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 24, height: 24)
                            .background(Theme.purple, in: Circle())
                    }
                }
            }
            .padding(12)
            .background(isSelected ? Theme.purple.opacity(0.10) : .white, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    private var previewText: String {
        guard let lastMessage else { return "No messages yet" }
        let senderName = members.first { $0.id == lastMessage.senderId }?.displayName
        if members.count > 2, let senderName {
            return "\(senderName): \(lastMessage.content)"
        }
        return lastMessage.content
    }
}

private struct SearchView: View {
    let viewModel: ContextlyViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var lastQuery = ""
    @State private var results: [SearchResult] = []
    @State private var isSearching = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    TextField("Ask about the conversation", text: $query)
                        .textFieldStyle(.roundedBorder)
                        .submitLabel(.search)
                        .onSubmit { runSearch() }

                    Button(isSearching ? "Searching" : "Search") {
                        runSearch()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSearching)
                }
                .padding()
                .background(.white)

                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(results) { result in
                            SearchResultRow(result: result, sender: viewModel.user(for: result.message.senderId))
                        }

                        if !lastQuery.isEmpty && results.isEmpty && !isSearching {
                            ContentUnavailableView(
                                "No exact matches",
                                systemImage: "sparkle.magnifyingglass",
                                description: Text("Try asking about a person, place, backend, database, meeting time, or search.")
                            )
                            .padding(.top, 80)
                        }
                    }
                    .padding(16)
                }
                .background(Theme.background)
                .overlay {
                    if lastQuery.isEmpty && !isSearching {
                        ContentUnavailableView(
                            "AI Search",
                            systemImage: "sparkle.magnifyingglass",
                            description: Text("Type a question, then tap Search or press return.")
                        )
                    }

                    if isSearching {
                        ProgressView("Searching")
                    }
                }
            }
            .navigationTitle("AI Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func runSearch() {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return }

        lastQuery = trimmedQuery
        isSearching = true
        Task {
            results = await viewModel.search(trimmedQuery)
            isSearching = false
        }
    }
}

private struct MessageBubble: View {
    let message: ContextlyMessage
    let sender: ContextlyUser?
    let isCurrentUser: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: 9) {
            if isCurrentUser { Spacer(minLength: 54) } else { avatar }

            VStack(alignment: isCurrentUser ? .trailing : .leading, spacing: 5) {
                if !isCurrentUser {
                    Text(sender?.displayName ?? "Unknown")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 4)
                }

                Text(message.content)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(isCurrentUser ? .white : Theme.ink)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(isCurrentUser ? Theme.purple : .white, in: RoundedRectangle(cornerRadius: 9))

                Text(message.createdAt, style: .time)
                    .font(.caption)
                    .foregroundStyle(isCurrentUser ? Theme.purple.opacity(0.75) : .secondary)
                    .padding(.horizontal, 4)
            }

            if !isCurrentUser { Spacer(minLength: 54) }
        }
    }

    private var avatar: some View {
        AvatarView(name: sender?.displayName ?? "Unknown", size: 32, tint: Theme.tint(for: message.senderId))
    }
}

private struct SearchResultRow: View {
    let result: SearchResult
    let sender: ContextlyUser?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AvatarView(name: sender?.displayName ?? "Unknown", size: 38, tint: Theme.tint(for: result.message.senderId))

            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text(sender?.displayName ?? "Unknown")
                        .font(.headline)
                    Spacer()
                    if let score = result.score {
                        Text(score, format: .number.precision(.fractionLength(2)))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Text(result.message.content)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.ink)

                Text(result.message.createdAt, style: .time)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .background(.white, in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

private struct HeaderButton: View {
    let systemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .frame(width: 36, height: 36)
                .background(Theme.softGray, in: Circle())
        }
        .buttonStyle(.plain)
    }
}

private struct UserChip: View {
    let user: ContextlyUser
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                AvatarView(name: user.displayName, size: 28, tint: Theme.tint(for: user.id))
                Text(user.displayName)
                    .font(.system(size: 14, weight: .semibold))
            }
            .padding(.leading, 6)
            .padding(.trailing, 12)
            .padding(.vertical, 6)
            .foregroundStyle(isSelected ? Theme.purple : Theme.ink)
            .background(isSelected ? Theme.purple.opacity(0.14) : Theme.softGray, in: Capsule())
            .overlay(Capsule().stroke(isSelected ? Theme.purple.opacity(0.45) : .clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

private struct AvatarView: View {
    let name: String
    let size: CGFloat
    let tint: Color

    var body: some View {
        ZStack {
            Circle().fill(tint.opacity(0.16))
            Circle().stroke(tint.opacity(0.25), lineWidth: 1)
            Text(initials)
                .font(.system(size: size * 0.36, weight: .bold))
                .foregroundStyle(tint)
        }
        .frame(width: size, height: size)
    }

    private var initials: String {
        String(name.split(separator: " ").prefix(2).compactMap(\.first)).uppercased()
    }
}

private struct SettingsView: View {
    @Binding var projectURL: String
    @Binding var publishableKey: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Supabase") {
                    TextField("https://project-ref.supabase.co", text: $projectURL)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                    SecureField("Publishable key", text: $publishableKey)
                        .textInputAutocapitalization(.never)
                }

                Section {
                    Text("Use a publishable or anon key only. The app talks to REST tables for messages and to the contextly-search Edge Function for semantic search.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Backend")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private enum Theme {
    static let purple = Color(red: 0.47, green: 0.36, blue: 0.92)
    static let ink = Color(red: 0.10, green: 0.10, blue: 0.18)
    static let softGray = Color(red: 0.94, green: 0.94, blue: 0.97)
    static let background = Color(red: 0.97, green: 0.97, blue: 0.98)

    static func tint(for id: UUID) -> Color {
        let palette = [
            Color(red: 0.47, green: 0.36, blue: 0.92),
            Color(red: 0.16, green: 0.58, blue: 0.78),
            Color(red: 0.86, green: 0.33, blue: 0.42),
            Color(red: 0.18, green: 0.62, blue: 0.44)
        ]
        return palette[abs(id.uuidString.hashValue) % palette.count]
    }
}

#Preview {
    ContentView()
}
