import SwiftUI

struct EditTaskView: View {
    let task: FamilyTask

    var body: some View {
        TaskEditorView(mode: .edit(task))
    }
}
