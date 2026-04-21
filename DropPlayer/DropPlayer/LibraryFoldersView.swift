import SwiftUI

/// Shows all library folders and lets the user add or remove them.
struct LibraryFoldersView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var library: LibraryViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var showFolderPicker = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.libraryGradient
                    .ignoresSafeArea()

                List {
                    ForEach(settings.musicFolderPaths, id: \.self) { path in
                        HStack {
                            Image(systemName: "folder.fill")
                                .foregroundStyle(Theme.accentColor)
                            Text(path)
                                .font(.body)
                        }
                    }
                    .onDelete(perform: removeFolders)
                }
                .navigationTitle("Library Folders")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            showFolderPicker = true
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
                .overlay {
                    if settings.musicFolderPaths.isEmpty {
                        ContentUnavailableView(
                            "No Folders",
                            systemImage: "folder.badge.questionmark",
                            description: Text("Tap + to add a Dropbox folder to your library.")
                        )
                    }
                }
            }
            .sheet(isPresented: $showFolderPicker) {
                FolderPickerView(isInitialSetup: false)
            }
        }
    }

    private func removeFolders(at offsets: IndexSet) {
        settings.musicFolderPaths.remove(atOffsets: offsets)
        Task {
            await library.rescanLibrary(at: settings.musicFolderPaths)
        }
    }
}
