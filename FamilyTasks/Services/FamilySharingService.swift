import CloudKit
import SwiftUI
import UIKit

enum FamilySharingService {
    static let container = CKContainer.default()

    static func sharingController() -> UICloudSharingController {
        UICloudSharingController { _, completion in
            let database = container.privateCloudDatabase
            let rootRecord = CKRecord(recordType: "FamilyTaskList")
            rootRecord["name"] = "Family Tasks" as CKRecordValue

            let share = CKShare(rootRecord: rootRecord)
            share[CKShare.SystemFieldKey.title] = "Family Tasks" as CKRecordValue
            share.publicPermission = .none

            let records: [CKRecord] = [rootRecord, share]
            let operation = CKModifyRecordsOperation(recordsToSave: records, recordIDsToDelete: nil)
            operation.savePolicy = .ifServerRecordUnchanged
            operation.modifyRecordsResultBlock = { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success:
                        completion(share, container, nil)
                    case .failure(let error):
                        completion(nil, nil, error)
                    }
                }
            }
            database.add(operation)
        }
    }
}

struct CloudSharingView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = FamilySharingService.sharingController()
        controller.availablePermissions = [.allowPrivate, .allowReadWrite]
        return controller
    }

    func updateUIViewController(_ uiViewController: UICloudSharingController, context: Context) {}
}
