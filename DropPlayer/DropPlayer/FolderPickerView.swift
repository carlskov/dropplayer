import SwiftUI
import SwiftyDropbox

/// Lets the user navigate their Dropbox and pick the root music folder.
struct FolderPickerView: View {
    /// When true, this is part of initial onboarding — no back button should dismiss.
    var isInitialSetup: Bool = false

    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var library: LibraryViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var currentPath: String = "/"
    @State private var folders: [Files.FolderMetadata] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var navigationStack: [String] = []

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.libraryGradient
                    .ignoresSafeArea()

                Group {
                    if isLoading {
                        ProgressView("Loading folders…")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if let error = errorMessage {
                        errorView(message: error)
                    } else {
                        folderList
                    }
                }
                .navigationTitle(currentPath == "/" ? "Dropbox" : lastComponent(of: currentPath))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }

                    if !navigationStack.isEmpty {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button {
                                navigateUp()
                            } label: {
                                Label("Back", systemImage: "chevron.left")
                            }
                        }
                    }

                    ToolbarItem(placement: .primaryAction) {
                        Button(isInitialSetup ? "Use This Folder" : "Add This Folder") {
                            selectFolder(currentPath)
                        }
                        .bold()
                        .disabled(settings.musicFolderPaths.contains(currentPath))
                    }
                }
            }
        }
        .task { await loadFolders(at: currentPath) }
    }

    // MARK: - Sub-views

    private var folderList: some View {
        List {
            if folders.isEmpty {
                Text("No sub-folders found")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(folders, id: \.pathLower) { folder in
                    Button {
                        navigateInto(folder)
                    } label: {
                        HStack {
                            Image(systemName: "folder.fill")
                                .foregroundStyle(Theme.accentColor)
                            Text(folder.name)
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.footnote)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.orange)
            Text(message)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button("Retry") {
                Task { await loadFolders(at: currentPath) }
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Navigation

    private func navigateInto(_ folder: Files.FolderMetadata) {
        let path = folder.pathLower ?? folder.name
        navigationStack.append(currentPath)
        currentPath = path
        Task { await loadFolders(at: path) }
    }

    private func navigateUp() {
        guard let previous = navigationStack.popLast() else { return }
        currentPath = previous
        Task { await loadFolders(at: previous) }
    }

    // MARK: - Dropbox

    private func loadFolders(at path: String) async {
        isLoading = true
        errorMessage = nil
        do {
            let entries = try await DropboxBrowserService.shared.listFolder(path: path)
            folders = entries.compactMap { $0 as? Files.FolderMetadata }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func selectFolder(_ path: String) {
        if !settings.musicFolderPaths.contains(path) {
            settings.musicFolderPaths.append(path)
        }
        Task {
            await library.scanLibrary(at: settings.musicFolderPaths)
        }
        dismiss()
    }

    private func lastComponent(of path: String) -> String {
        (path as NSString).lastPathComponent
    }
}
