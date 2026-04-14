import SwiftUI
import PhotosUI
import MessageUI
import Supabase

struct SupportFormView: View {
    @Environment(AuthService.self) private var authService
    @Environment(\.dismiss) private var dismiss
    @State private var email: String = ""
    @State private var message: String = ""
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var attachedImage: UIImage?
    @State private var isSubmitting: Bool = false
    @State private var showMailComposer: Bool = false
    @State private var showMailUnavailableAlert: Bool = false
    @State private var showSuccessAlert: Bool = false
    @State private var showErrorAlert: Bool = false
    @State private var errorText: String = ""

    private let supportEmail = "support@vinetrack.app"

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "person.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(authService.userName.isEmpty ? "User" : authService.userName)
                                .font(.subheadline.weight(.medium))
                            Text(email)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Your Details")
                }

                Section {
                    TextEditor(text: $message)
                        .frame(minHeight: 150)
                        .overlay(alignment: .topLeading) {
                            if message.isEmpty {
                                Text("Describe your issue or feedback...")
                                    .foregroundStyle(.tertiary)
                                    .padding(.top, 8)
                                    .padding(.leading, 4)
                                    .allowsHitTesting(false)
                            }
                        }
                } header: {
                    Text("Message")
                }

                Section {
                    if let attachedImage {
                        HStack(spacing: 12) {
                            Image(uiImage: attachedImage)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 80, height: 80)
                                .clipShape(.rect(cornerRadius: 8))

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Screenshot attached")
                                    .font(.subheadline.weight(.medium))
                                let size = attachedImage.size
                                Text("\(Int(size.width)) × \(Int(size.height))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Button(role: .destructive) {
                                withAnimation {
                                    self.attachedImage = nil
                                    selectedPhotoItem = nil
                                }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                        Label(attachedImage != nil ? "Change Screenshot" : "Attach Screenshot", systemImage: "photo.badge.plus")
                    }
                } header: {
                    Text("Attachment")
                } footer: {
                    Text("Optionally attach a screenshot to help us understand the issue.")
                }

                Section {
                    Button {
                        submitSupportRequest()
                    } label: {
                        HStack {
                            Spacer()
                            if isSubmitting {
                                ProgressView()
                                    .controlSize(.small)
                                    .padding(.trailing, 8)
                            }
                            Text(isSubmitting ? "Sending..." : "Submit")
                                .font(.headline)
                            Spacer()
                        }
                    }
                    .disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmitting)
                }
            }
            .navigationTitle("Contact Support")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task {
                email = authService.userEmail
            }
            .onChange(of: selectedPhotoItem) { _, newItem in
                handlePhotoSelection(newItem)
            }
            .sheet(isPresented: $showMailComposer) {
                MailComposerView(
                    toEmail: supportEmail,
                    subject: "VineTrack Support Request",
                    body: buildEmailBody(),
                    attachmentImage: attachedImage,
                    onFinish: { result in
                        showMailComposer = false
                        if result == .sent {
                            showSuccessAlert = true
                        }
                    }
                )
                .ignoresSafeArea()
            }
            .alert("Request Sent", isPresented: $showSuccessAlert) {
                Button("Done") { dismiss() }
            } message: {
                Text("Your support request has been submitted. We'll get back to you as soon as possible.")
            }
            .alert("Unable to Send", isPresented: $showMailUnavailableAlert) {
                Button("Copy Email") {
                    UIPasteboard.general.string = supportEmail
                }
                Button("OK", role: .cancel) {}
            } message: {
                Text("Mail is not configured on this device. Please email us directly at \(supportEmail)")
            }
            .alert("Error", isPresented: $showErrorAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorText)
            }
        }
    }

    private func submitSupportRequest() {
        if MFMailComposeViewController.canSendMail() {
            showMailComposer = true
        } else {
            submitViaSupabase()
        }
    }

    private func submitViaSupabase() {
        guard isSupabaseConfigured else {
            showMailUnavailableAlert = true
            return
        }

        isSubmitting = true
        Task {
            do {
                var imageBase64: String?
                if let attachedImage, let data = attachedImage.jpegData(compressionQuality: 0.6) {
                    imageBase64 = data.base64EncodedString()
                }

                let request = SupportRequest(
                    user_email: email,
                    user_name: authService.userName,
                    user_id: authService.userId,
                    message: message,
                    image_base64: imageBase64,
                    app_version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
                    device_model: UIDevice.current.model,
                    ios_version: UIDevice.current.systemVersion
                )

                try await supabase.from("support_requests")
                    .insert(request)
                    .execute()

                isSubmitting = false
                showSuccessAlert = true
            } catch {
                isSubmitting = false
                errorText = "Failed to submit: \(error.localizedDescription)"
                showErrorAlert = true
            }
        }
    }

    private func buildEmailBody() -> String {
        var body = message
        body += "\n\n---"
        body += "\nFrom: \(authService.userName) (\(email))"
        body += "\nApp Version: \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown")"
        body += "\nDevice: \(UIDevice.current.model)"
        body += "\niOS: \(UIDevice.current.systemVersion)"
        if let userId = authService.userId {
            body += "\nUser ID: \(userId)"
        }
        return body
    }

    private func handlePhotoSelection(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            if let data = try? await item.loadTransferable(type: Data.self),
               let uiImage = UIImage(data: data) {
                let maxDimension: CGFloat = 1200
                let scale = min(maxDimension / uiImage.size.width, maxDimension / uiImage.size.height, 1.0)
                if scale < 1.0 {
                    let newSize = CGSize(width: uiImage.size.width * scale, height: uiImage.size.height * scale)
                    let renderer = UIGraphicsImageRenderer(size: newSize)
                    let resized = renderer.image { _ in
                        uiImage.draw(in: CGRect(origin: .zero, size: newSize))
                    }
                    attachedImage = resized
                } else {
                    attachedImage = uiImage
                }
            }
        }
    }
}

nonisolated struct SupportRequest: Codable, Sendable {
    let user_email: String
    let user_name: String
    let user_id: String?
    let message: String
    let image_base64: String?
    let app_version: String
    let device_model: String
    let ios_version: String
}

struct MailComposerView: UIViewControllerRepresentable {
    let toEmail: String
    let subject: String
    let body: String
    let attachmentImage: UIImage?
    let onFinish: (MFMailComposeResult) -> Void

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let composer = MFMailComposeViewController()
        composer.mailComposeDelegate = context.coordinator
        composer.setToRecipients([toEmail])
        composer.setSubject(subject)
        composer.setMessageBody(body, isHTML: false)

        if let image = attachmentImage, let data = image.jpegData(compressionQuality: 0.8) {
            composer.addAttachmentData(data, mimeType: "image/jpeg", fileName: "screenshot.jpg")
        }

        return composer
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let onFinish: (MFMailComposeResult) -> Void

        init(onFinish: @escaping (MFMailComposeResult) -> Void) {
            self.onFinish = onFinish
        }

        nonisolated func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
            Task { @MainActor in
                onFinish(result)
            }
        }
    }
}
