import SwiftUI

struct ChatView: View {
    @ObservedObject var app: AppContainer

    let friend: Friend
    @State private var text = ""
    @State private var messages: [String] = []

    var body: some View {
        VStack(spacing: 0) {
            if messages.isEmpty {
                ContentUnavailableView("No messages", systemImage: "message", description: Text("There are no messages here"))
            } else {
                List(messages, id: \.self) { message in
                    Text(RichTextFormatter.toAttributedString(message))
                        .lineLimit(8)
                }
            }

            HStack {
                TextField("Message \(friend.contactUsername)...", text: $text, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)
                Button("Send") {
                    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                    messages.insert(text, at: 0)
                    app.hubClient.send(target: "SendMessage", arguments: [["content": text]])
                    text = ""
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .background(.ultraThinMaterial)
        }
        .navigationTitle(friend.contactUsername)
        .navigationBarTitleDisplayMode(.inline)
    }
}
