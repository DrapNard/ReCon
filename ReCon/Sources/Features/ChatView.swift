import SwiftUI
import AVFoundation
import UIKit

struct ChatView: View {
    @ObservedObject var app: AppContainer

    let friend: Friend
    @State private var text = ""
    @State private var messages: [Message] = []
    @State private var conversationAccent: Color = .accentColor
    @State private var loading = false
    @State private var errorText: String?
    @State private var sessionsForInvite: [Session] = []
    @State private var showInvitePicker = false
    @State private var listProxy: ScrollViewProxy?
    @State private var isVoiceRecording = false
    @State private var voiceRecorder: AVAudioRecorder?
    @State private var voiceRecordingURL: URL?
    @State private var voiceRecordingDuration: TimeInterval = 0
    @State private var voiceMeterLevels: [CGFloat] = Array(repeating: 0.12, count: 28)
    @State private var voiceMeterTimer: Timer?
    @State private var receiveMessageHandlerID: UUID?
    @State private var messageSentHandlerID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            if loading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if messages.isEmpty {
                ContentUnavailableView("No messages", systemImage: "message", description: Text("There are no messages here"))
            } else {
                ScrollViewReader { proxy in
                    List(messages) { message in
                        let isMine = message.senderId == app.auth.userId
                        HStack(alignment: .bottom, spacing: 8) {
                            if isMine {
                                Spacer(minLength: 40)
                            } else {
                                ChatParticipantAvatar(
                                    username: friend.contactUsername,
                                    iconURL: friend.profileIconUrl,
                                    environment: app.environment,
                                    size: 30
                                )
                            }

                            MessageBubbleContentView(
                                message: message,
                                isMine: isMine,
                                accentColor: conversationAccent,
                                environment: app.environment,
                                app: app
                            )
                            .frame(maxWidth: UIScreen.main.bounds.width * 0.72, alignment: isMine ? .trailing : .leading)

                            if isMine {
                                ChatParticipantAvatar(
                                    username: "Me",
                                    iconURL: nil,
                                    environment: app.environment,
                                    size: 30
                                )
                            } else {
                                Spacer(minLength: 40)
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                        .id(message.id)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }
                    .reconListScreen(backdrop: .chat, accent: conversationAccent)
                    .onAppear {
                        listProxy = proxy
                        scrollToLatest(animated: false)
                    }
                }
            }

            if isVoiceRecording {
                VoiceRecordingLiveView(
                    levels: voiceMeterLevels,
                    duration: voiceRecordingDuration,
                    accentColor: conversationAccent
                )
                .padding(.horizontal, 12)
                .padding(.top, 8)
            }

            HStack(spacing: 10) {
                Menu {
                    Button {
                        showInvitePicker = true
                    } label: {
                        Label("Send Session Invite", systemImage: "person.3.fill")
                    }

                    Button {
                        sendInviteRequest()
                    } label: {
                        Label("Request Invite", systemImage: "questionmark.circle")
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .bold))
                        .frame(width: 36, height: 36)
                        .background(.ultraThinMaterial, in: Circle())
                }

                TextField("Message \(friend.contactUsername)...", text: $text, axis: .vertical)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .lineLimit(1...4)

                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button {
                        toggleVoiceRecording()
                    } label: {
                        Image(systemName: isVoiceRecording ? "stop.fill" : "mic.fill")
                            .font(.system(size: 16, weight: .bold))
                            .frame(width: 36, height: 36)
                            .background(isVoiceRecording ? Color.red : conversationAccent, in: Circle())
                            .foregroundStyle(.white)
                    }
                } else {
                    Button {
                        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        let now = Date()
                        let outgoing = Message(
                            id: "MSG-\(UUID().uuidString)",
                            recipientId: friend.contactUserId,
                            senderId: app.auth.userId,
                            type: .text,
                            content: trimmed,
                            sendTime: now,
                            lastUpdateTime: now,
                            state: .local
                        )
                        messages.append(outgoing)
                        let payload: [String: Any] = [
                            "id": outgoing.id,
                            "recipientId": outgoing.recipientId,
                            "senderId": outgoing.senderId,
                            "ownerId": outgoing.senderId,
                            "messageType": "Text",
                            "content": outgoing.content,
                            "sendTime": ISO8601DateFormatter().string(from: now)
                        ]
                        let sentNow = app.hubClient.send(target: "SendMessage", arguments: [payload])
                        if !sentNow {
                            errorText = "Reconnecting... message queued."
                        }
                        text = ""
                    } label: {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 16, weight: .bold))
                            .frame(width: 36, height: 36)
                            .background(conversationAccent, in: Circle())
                            .foregroundStyle(.white)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 10)
            .background(.thinMaterial)
        }
        .background(
            ZStack {
                Color.black
                LinearGradient(
                    colors: [conversationAccent.opacity(0.78), conversationAccent.opacity(0.42), conversationAccent.opacity(0.12)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                RadialGradient(
                    colors: [conversationAccent.opacity(0.50), .clear],
                    center: .bottomTrailing,
                    startRadius: 80,
                    endRadius: 720
                )
            }
                .ignoresSafeArea()
        )
        .navigationTitle(friend.contactUsername)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarBackground(conversationAccent.opacity(0.36), for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    SessionUserProfileView(
                        app: app,
                        userId: friend.contactUserId,
                        fallbackUsername: friend.contactUsername,
                        initialUser: nil,
                        initialContactStatus: friend.contactStatus ?? (friend.isAccepted == true ? "accepted" : "none")
                    )
                } label: {
                    Image(systemName: "person.crop.circle")
                }
            }
        }
        .sheet(isPresented: $showInvitePicker) {
            NavigationStack {
                List(sessionsForInvite) { session in
                    Button {
                        sendSessionInvite(session)
                        showInvitePicker = false
                    } label: {
                        HStack(spacing: 10) {
                            SharedThumbnailView(urlString: session.thumbnailUrl, environment: app.environment, size: 42, fallbackSystemName: "person.3")
                            VStack(alignment: .leading, spacing: 4) {
                                Text(RichTextFormatter.toAttributedString(session.name))
                                    .lineLimit(2)
                                Text("Hosted by \(session.hostUsername)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .navigationTitle("Invite To Session")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Close") { showInvitePicker = false }
                    }
                }
                .task { await loadSessionsForInvites() }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let errorText {
                Text(errorText)
                    .foregroundStyle(.red)
                    .padding(8)
            }
        }
        .task(id: friend.profileIconUrl ?? friend.contactUserId) {
            let iconKey = friend.profileIconUrl?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let tintKey = iconKey.isEmpty ? friend.contactUserId : iconKey
            conversationAccent = StableTintPalette.color(for: tintKey, fallback: .accentColor)
        }
        .task {
            await loadMessages()
            receiveMessageHandlerID = app.hubClient.addHandler("ReceiveMessage") { args in
                guard let first = args.first as? [String: Any] else { return }
                let incoming = Message(map: first)
                Task { @MainActor in
                    if incoming.senderId == friend.contactUserId || incoming.recipientId == friend.contactUserId {
                        if !messages.contains(where: { $0.id == incoming.id }) {
                            messages.append(incoming)
                            messages.sort { $0.sendTime < $1.sendTime }
                            scrollToLatest(animated: true)
                        }
                    }
                }
            }
            messageSentHandlerID = app.hubClient.addHandler("MessageSent") { args in
                guard let first = args.first as? [String: Any] else { return }
                let sent = Message(map: first)
                Task { @MainActor in
                    if sent.senderId == app.auth.userId, sent.recipientId == friend.contactUserId {
                        if let index = messages.firstIndex(where: { $0.id == sent.id }) {
                            messages[index] = sent
                        } else if !messages.contains(where: { $0.id == sent.id }) {
                            messages.append(sent)
                        }
                        messages.sort { $0.sendTime < $1.sendTime }
                        scrollToLatest(animated: true)
                    }
                }
            }
        }
        .onChange(of: messages.count) { _, _ in
            scrollToLatest(animated: true)
        }
        .onDisappear {
            stopVoiceMetering()
            voiceRecorder?.stop()
            voiceRecorder = nil
            isVoiceRecording = false
            if let receiveMessageHandlerID {
                app.hubClient.removeHandler("ReceiveMessage", id: receiveMessageHandlerID)
                self.receiveMessageHandlerID = nil
            }
            if let messageSentHandlerID {
                app.hubClient.removeHandler("MessageSent", id: messageSentHandlerID)
                self.messageSentHandlerID = nil
            }
        }
    }

    private func loadMessages() async {
        loading = true
        defer { loading = false }
        do {
            messages = try await app.repository.fetchMessages(auth: app.auth, with: friend.contactUserId)
            errorText = nil
            scrollToLatest(animated: false)
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func loadSessionsForInvites() async {
        do {
            sessionsForInvite = try await app.repository.fetchSessions(auth: app.auth)
        } catch {
            // Keep picker empty on errors.
        }
    }

    private func sendSessionInvite(_ session: Session) {
        let payloadMap = makeSessionInvitePayload(session)
        guard let payloadData = try? JSONSerialization.data(withJSONObject: payloadMap),
              let payloadContent = String(data: payloadData, encoding: .utf8) else { return }

        let now = Date()
        let inviteMessage = Message(
            id: "MSG-\(UUID().uuidString)",
            recipientId: friend.contactUserId,
            senderId: app.auth.userId,
            type: .sessionInvite,
            content: payloadContent,
            sendTime: now,
            lastUpdateTime: now,
            state: .local
        )
        messages.append(inviteMessage)
        messages.sort { $0.sendTime < $1.sendTime }

        let wirePayload: [String: Any] = [
            "id": inviteMessage.id,
            "recipientId": inviteMessage.recipientId,
            "senderId": inviteMessage.senderId,
            "ownerId": inviteMessage.senderId,
            "messageType": "SessionInvite",
            "content": payloadContent,
            "sendTime": ISO8601DateFormatter().string(from: now)
        ]
        let sentNow = app.hubClient.send(target: "SendMessage", arguments: [wirePayload])
        if !sentNow {
            errorText = "Reconnecting... invite queued."
        }
    }

    private func makeSessionInvitePayload(_ session: Session) -> [String: Any] {
        [
            "name": session.name,
            "description": "",
            "tags": [],
            "sessionId": session.id,
            "hostUserId": "",
            "hostMachineId": "",
            "hostUsername": session.hostUsername,
            "universeId": "",
            "appVersion": "",
            "headlessHost": false,
            "sessionURLs": session.sessionURLs,
            "sessionUsers": session.sessionUsers.map { ["userID": $0.id, "username": $0.username, "isPresent": $0.isPresent] },
            "thumbnailUrl": session.thumbnailUrl,
            "joinedUsers": session.joinedUsers,
            "minActiveUsers": 0,
            "totalJoinedUsers": session.joinedUsers,
            "totalActiveUsers": session.joinedUsers,
            "maxUsers": session.maxUsers,
            "mobileFriendly": false,
            "sessionBeginTime": ISO8601DateFormatter().string(from: Date()),
            "lastUpdate": ISO8601DateFormatter().string(from: Date()),
            "accessLevel": "Anyone",
            "hideFromListing": false,
            "broadcastKey": "",
            "awayKickEnabled": false,
            "hasEnded": false,
            "isValid": true
        ]
    }

    private func sendInviteRequest() {
        let payload: [String: Any] = [
            "inviteRequestId": UUID().uuidString,
            "userIdToInvite": friend.contactUserId,
            "usernameToInvite": friend.contactUsername,
            "requestingFromUserId": app.auth.userId,
            "requestingFromUsername": app.auth.userId.replacingOccurrences(of: "U-", with: ""),
            "forSessionId": NSNull(),
            "forSessionName": NSNull(),
            "isContactOfHost": NSNull(),
            "response": NSNull(),
            "invite": NSNull()
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let content = String(data: data, encoding: .utf8) else { return }

        let now = Date()
        let requestMessage = Message(
            id: "MSG-\(UUID().uuidString)",
            recipientId: friend.contactUserId,
            senderId: app.auth.userId,
            type: .inviteRequest,
            content: content,
            sendTime: now,
            lastUpdateTime: now,
            state: .local
        )
        messages.append(requestMessage)
        messages.sort { $0.sendTime < $1.sendTime }
        scrollToLatest(animated: true)

        let wirePayload: [String: Any] = [
            "id": requestMessage.id,
            "recipientId": requestMessage.recipientId,
            "senderId": requestMessage.senderId,
            "ownerId": requestMessage.senderId,
            "messageType": "InviteRequest",
            "content": requestMessage.content,
            "sendTime": ISO8601DateFormatter().string(from: now)
        ]
        let sentNow = app.hubClient.send(target: "SendMessage", arguments: [wirePayload])
        if !sentNow {
            errorText = "Reconnecting... request queued."
        }
    }

    private func toggleVoiceRecording() {
        if isVoiceRecording {
            stopVoiceRecordingAndSend()
        } else {
            startVoiceRecording()
        }
    }

    private func startVoiceRecording() {
        AVAudioApplication.requestRecordPermission { granted in
            guard granted else { return }
            DispatchQueue.main.async {
                do {
                    let session = AVAudioSession.sharedInstance()
                    try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
                    try session.setActive(true)

                    let url = FileManager.default.temporaryDirectory.appendingPathComponent("voice-\(UUID().uuidString).m4a")
                    let settings: [String: Any] = [
                        AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                        AVSampleRateKey: 44_100,
                        AVNumberOfChannelsKey: 1,
                        AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
                    ]
                    let recorder = try AVAudioRecorder(url: url, settings: settings)
                    recorder.isMeteringEnabled = true
                    recorder.record()
                    voiceRecorder = recorder
                    voiceRecordingURL = url
                    voiceRecordingDuration = 0
                    voiceMeterLevels = Array(repeating: 0.12, count: 28)
                    isVoiceRecording = true
                    startVoiceMetering()
                } catch {
                    errorText = "Unable to start voice recording."
                    isVoiceRecording = false
                }
            }
        }
    }

    private func stopVoiceRecordingAndSend() {
        guard let recorder = voiceRecorder else {
            isVoiceRecording = false
            return
        }
        recorder.stop()
        isVoiceRecording = false
        voiceRecorder = nil
        stopVoiceMetering()

        guard let url = voiceRecordingURL,
              FileManager.default.fileExists(atPath: url.path) else {
            errorText = "Failed to read recorded voice message."
            return
        }

        let now = Date()
        let messageID = "MSG-\(UUID().uuidString)"
        let message = Message(
            id: messageID,
            recipientId: friend.contactUserId,
            senderId: app.auth.userId,
            type: .sound,
            content: "",
            sendTime: now,
            lastUpdateTime: now,
            state: .local
        )
        messages.append(message)
        messages.sort { $0.sendTime < $1.sendTime }
        scrollToLatest(animated: true)

        Task {
            do {
                let oggURL = try transcodeRecordingToOgg(inputURL: url)
                let record = try await app.repository.uploadVoiceClipMessageRecord(auth: app.auth, fileURL: oggURL, messageID: messageID)
                let contentData = try JSONSerialization.data(withJSONObject: record)
                guard let content = String(data: contentData, encoding: .utf8) else {
                    throw AppError.unknown("Failed to encode voice payload.")
                }
                let wirePayload: [String: Any] = [
                    "id": message.id,
                    "recipientId": message.recipientId,
                    "senderId": message.senderId,
                    "ownerId": message.senderId,
                    "messageType": "Sound",
                    "content": content,
                    "sendTime": ISO8601DateFormatter().string(from: now)
                ]
                let sentNow = app.hubClient.send(target: "SendMessage", arguments: [wirePayload])
                await MainActor.run {
                    if let idx = messages.firstIndex(where: { $0.id == message.id }) {
                        messages[idx] = Message(
                            id: message.id,
                            recipientId: message.recipientId,
                            senderId: message.senderId,
                            type: .sound,
                            content: content,
                            sendTime: message.sendTime,
                            lastUpdateTime: Date(),
                            state: sentNow ? .sent : .local
                        )
                    }
                    if !sentNow {
                        errorText = "Reconnecting... voice message queued."
                    }
                }
            } catch {
                await MainActor.run {
                    messages.removeAll(where: { $0.id == message.id })
                    errorText = "Failed to send voice message: \(error.localizedDescription)"
                }
            }
        }
    }

    private func transcodeRecordingToOgg(inputURL: URL) throws -> URL {
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("voice-\(UUID().uuidString).ogg")
        let inputFile: AVAudioFile
        do {
            inputFile = try AVAudioFile(
                forReading: inputURL,
                commonFormat: .pcmFormatFloat32,
                interleaved: false
            )
        } catch {
            throw AppError.unknown("Unable to read source recording.")
        }
        let outputSettings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatOpus),
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 64_000
        ]
        let outputFile: AVAudioFile
        do {
            outputFile = try AVAudioFile(forWriting: outputURL, settings: outputSettings)
        } catch {
            throw AppError.unknown("Native OGG encoder unavailable on this runtime.")
        }
        let pcmFormat = inputFile.processingFormat
        guard pcmFormat.commonFormat == .pcmFormatFloat32 || pcmFormat.commonFormat == .pcmFormatInt16 else {
            throw AppError.unknown("Source decode did not produce PCM audio.")
        }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: pcmFormat, frameCapacity: 4096) else {
            throw AppError.unknown("Failed to allocate audio buffer.")
        }
        while true {
            do {
                try inputFile.read(into: buffer)
            } catch {
                throw AppError.unknown("Failed while decoding source recording.")
            }
            if buffer.frameLength == 0 { break }
            do {
                try outputFile.write(from: buffer)
            } catch {
                throw AppError.unknown("Failed while encoding OGG stream.")
            }
            buffer.frameLength = 0
        }
        let outData: Data
        do {
            outData = try Data(contentsOf: outputURL)
        } catch {
            throw AppError.unknown("Unable to read transcoded OGG output.")
        }
        let signature = outData.count >= 4 ? String(decoding: outData.prefix(4), as: UTF8.self) : ""
        guard signature == "OggS" else {
            throw AppError.unknown("Native OGG transcode failed on this runtime.")
        }
        return outputURL
    }

    private func startVoiceMetering() {
        stopVoiceMetering()
        voiceMeterTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { _ in
            guard let recorder = voiceRecorder else { return }
            recorder.updateMeters()
            voiceRecordingDuration = recorder.currentTime
            let power = recorder.averagePower(forChannel: 0)
            let normalized = max(0.08, min(1.0, CGFloat((power + 55) / 55)))
            voiceMeterLevels.append(normalized)
            if voiceMeterLevels.count > 28 {
                voiceMeterLevels.removeFirst(voiceMeterLevels.count - 28)
            }
        }
    }

    private func stopVoiceMetering() {
        voiceMeterTimer?.invalidate()
        voiceMeterTimer = nil
    }

    private func scrollToLatest(animated: Bool) {
        guard let last = messages.last?.id else { return }
        DispatchQueue.main.async {
            if animated {
                withAnimation(.easeOut(duration: 0.2)) {
                    listProxy?.scrollTo(last, anchor: .bottom)
                }
            } else {
                listProxy?.scrollTo(last, anchor: .bottom)
            }
        }
    }
}

private struct VoiceRecordingLiveView: View {
    let levels: [CGFloat]
    let duration: TimeInterval
    let accentColor: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "mic.fill")
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(.red, in: Circle())

            HStack(alignment: .center, spacing: 2) {
                ForEach(Array(levels.enumerated()), id: \.offset) { _, level in
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(.white.opacity(0.92))
                        .frame(width: 3, height: max(6, 26 * level))
                }
            }
            .frame(height: 30)

            Spacer(minLength: 0)

            Text(format(duration))
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(.white.opacity(0.92))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            LinearGradient(
                colors: [accentColor.opacity(0.7), accentColor.opacity(0.45)],
                startPoint: .leading,
                endPoint: .trailing
            ),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        )
    }

    private func format(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let mm = String(format: "%02d", total / 60)
        let ss = String(format: "%02d", total % 60)
        return "\(mm):\(ss)"
    }
}

private struct ChatParticipantAvatar: View {
    let username: String
    let iconURL: String?
    let environment: AppEnvironment
    let size: CGFloat

    var body: some View {
        if let iconURL, let url = AssetURLResolver.resolveImageURL(iconURL, environment: environment) {
            AsyncImage(url: url) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                placeholder
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(.white.opacity(0.24), lineWidth: 1))
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        Circle()
            .fill(.white.opacity(0.18))
            .frame(width: size, height: size)
            .overlay {
                Text(String(username.prefix(1)).uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .overlay(Circle().strokeBorder(.white.opacity(0.2), lineWidth: 1))
    }
}

private struct MessageBubbleContentView: View {
    let message: Message
    let isMine: Bool
    let accentColor: Color
    let environment: AppEnvironment
    let app: AppContainer

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch message.type {
            case .sound:
                VoiceMessagePlayer(content: message.content, environment: environment)
            case .sessionInvite:
                SessionInviteView(content: message.content, environment: environment, app: app)
            case .inviteRequest:
                InviteRequestView(content: message.content)
            default:
                Text(RichTextFormatter.toAttributedString(message.content))
                    .lineLimit(8)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            (isMine ? accentColor.opacity(0.42) : Color.white.opacity(0.14)),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
    }
}

private struct VoiceMessagePlayer: View {
    let content: String
    let environment: AppEnvironment

    @State private var player: AVAudioPlayer?
    @State private var isPlaying = false
    @State private var duration: Double = 0
    @State private var currentTime: Double = 0
    @State private var timer: Timer?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button {
                    togglePlay()
                } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                }
                .buttonStyle(.bordered)

                Slider(value: Binding(
                    get: { duration == 0 ? 0 : currentTime / duration },
                    set: { newValue in
                        let target = duration * newValue
                        player?.currentTime = target
                        currentTime = target
                    }
                ))
            }
            Text("\(format(seconds: currentTime))/\(format(seconds: duration))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .task {
            await prepare()
        }
        .onDisappear {
            player?.pause()
            isPlaying = false
            timer?.invalidate()
            timer = nil
        }
    }

    private func prepare() async {
        guard
            let url = resolveAudioURL(),
            player == nil
        else { return }

        do {
            let data: Data
            if url.isFileURL {
                data = try Data(contentsOf: url)
            } else {
                let (remoteData, _) = try await URLSession.shared.data(from: url)
                data = remoteData
            }
            let audio = try AVAudioPlayer(data: data)
            audio.prepareToPlay()
            player = audio
            duration = audio.duration
            currentTime = audio.currentTime
            startTimer()
        } catch {
            // Keep silent fallback in UI.
        }
    }

    private func resolveAudioURL() -> URL? {
        guard
            let data = content.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        let asset = json["assetUri"] as? String
            ?? (json["asset"] as? [String: Any])?["assetUri"] as? String
        if let asset, asset.hasPrefix("data:audio"), let comma = asset.firstIndex(of: ",") {
            let header = asset[..<comma].lowercased()
            let ext: String
            if header.contains("audio/ogg") {
                ext = "ogg"
            } else if header.contains("audio/wav") {
                ext = "wav"
            } else {
                ext = "m4a"
            }

            let b64 = String(asset[asset.index(after: comma)...])
            if let data = Data(base64Encoded: b64) {
                let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("voice-received-\(UUID().uuidString).\(ext)")
                try? data.write(to: tmp)
                return tmp
            }
        }
        return AssetURLResolver.resolveMediaURL(asset, environment: environment)
            ?? AssetURLResolver.resolveImageURL(asset, environment: environment)
    }

    private func togglePlay() {
        guard let player else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
            startTimer()
        }
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { _ in
            guard let player else { return }
            currentTime = player.currentTime
            duration = player.duration
            if !player.isPlaying {
                isPlaying = false
            }
        }
    }

    private func format(seconds: Double) -> String {
        guard seconds.isFinite else { return "00:00" }
        let total = Int(seconds.rounded())
        let mm = String(format: "%02d", total / 60)
        let ss = String(format: "%02d", total % 60)
        return "\(mm):\(ss)"
    }
}

private struct SessionInviteView: View {
    let content: String
    let environment: AppEnvironment
    @ObservedObject var app: AppContainer

    @State private var parsedSession: Session?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let session = parsedSession {
                HStack(spacing: 10) {
                    SharedThumbnailView(urlString: session.thumbnailUrl, environment: environment, size: 44, fallbackSystemName: "person.3")
                    VStack(alignment: .leading, spacing: 2) {
                        Text(RichTextFormatter.toAttributedString(session.name))
                            .lineLimit(2)
                        Text("Hosted by \(session.hostUsername)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Text("\(session.joinedUsers)/\(session.maxUsers) Online")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                NavigationLink("Open Session") {
                    SessionDetailView(app: app, sessionID: session.id)
                }
                .buttonStyle(.bordered)

                if let worldURL = session.sessionURLs.first(where: { $0.lowercased().hasPrefix("resonite://") || $0.lowercased().hasPrefix("http") }),
                   let url = URL(string: worldURL) {
                    Button("Open World") {
                        UIApplication.shared.open(url)
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                Text("Session invite")
                    .font(.headline)
                Text("Unable to parse session payload.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .task {
            parsePayload()
        }
    }

    private func parsePayload() {
        guard
            let data = content.data(using: .utf8),
            let map = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            parsedSession = nil
            return
        }
        parsedSession = Session(map: map)
    }
}

private struct InviteRequestView: View {
    let content: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Invite Request")
                .font(.headline)
            Text(descriptionText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var descriptionText: String {
        guard
            let data = content.data(using: .utf8),
            let map = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return "Requested a session invite."
        }
        let username = (map["usernameToInvite"] as? String) ?? "User"
        if let forSessionName = map["forSessionName"] as? String, !forSessionName.isEmpty {
            return "\(username) requested to join \"\(forSessionName)\"."
        }
        return "\(username) requested a session invite."
    }
}
