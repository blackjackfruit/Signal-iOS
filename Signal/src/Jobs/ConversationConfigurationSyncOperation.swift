//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
class ConversationConfigurationSyncOperation: OWSOperation {

    enum ColorSyncOperationError: Error {
        case assertionError(description: String)
    }

    private var dbConnection: YapDatabaseConnection {
        return OWSPrimaryStorage.shared().dbReadConnection
    }

    private var messageSender: MessageSender {
        return Environment.current().messageSender
    }

    private var contactsManager: OWSContactsManager {
        return Environment.current().contactsManager
    }

    private var profileManager: OWSProfileManager {
        return OWSProfileManager.shared()
    }

    private var identityManager: OWSIdentityManager {
        return OWSIdentityManager.shared()
    }

    private let thread: TSThread

    @objc
    public init(thread: TSThread) {
        self.thread = thread
        super.init()
    }

    override public func run() {
        if let contactThread = thread as? TSContactThread {
            sync(contactThread: contactThread)
        } else if let groupThread = thread as? TSGroupThread {
            sync(groupThread: groupThread)
        } else {
            self.reportAssertionError(description: "unknown thread type")
        }
    }

    private func reportAssertionError(description: String) {
        let error = ColorSyncOperationError.assertionError(description: description)
        self.reportError(error)
    }

    private func sync(contactThread: TSContactThread) {
        guard let signalAccount: SignalAccount = self.contactsManager.fetchSignalAccount(forRecipientId: contactThread.contactIdentifier()) else {
            reportAssertionError(description: "unable to find signalAccount")
            return
        }

        let syncMessage: OWSSyncContactsMessage = OWSSyncContactsMessage(signalAccounts: [signalAccount],
                                                                                 identityManager: self.identityManager,
                                                                                 profileManager: self.profileManager)

        var dataSource: DataSource? = nil
        self.dbConnection.readWrite { transaction in
            let messageData: Data = syncMessage.buildPlainTextAttachmentData(with: transaction)
            dataSource = DataSourceValue.dataSource(withSyncMessageData: messageData)
            dataSource?.setShouldDeleteOnDeallocation()
        }

        guard let attachmentDataSource = dataSource else {
            self.reportAssertionError(description: "unable to build attachment data source")
            return
        }

        self.sendConfiguration(attachmentDataSource: attachmentDataSource, syncMessage: syncMessage)
    }

    private func sync(groupThread: TSGroupThread) {
        // TODO sync only the affected group
        // The current implementation works, but seems wasteful.
        // Does desktop handle single group sync correctly?
        // What does Android do?
        let syncMessage: OWSSyncGroupsMessage = OWSSyncGroupsMessage()

        var dataSource: DataSource? = nil
        self.dbConnection.read { transaction in
            let messageData: Data = syncMessage.buildPlainTextAttachmentData(with: transaction)
            dataSource = DataSourceValue.dataSource(withSyncMessageData: messageData)
            dataSource?.setShouldDeleteOnDeallocation()
        }

        guard let attachmentDataSource = dataSource else {
            self.reportAssertionError(description: "unable to build attachment data source")
            return
        }

        self.sendConfiguration(attachmentDataSource: attachmentDataSource, syncMessage: syncMessage)
    }

    private func sendConfiguration(attachmentDataSource: DataSource, syncMessage: OWSOutgoingSyncMessage) {
        self.messageSender.enqueueTemporaryAttachment(attachmentDataSource,
                                                      contentType: OWSMimeTypeApplicationOctetStream,
                                                      in: syncMessage,
                                                      success: {
                                                        self.reportSuccess()
        },
                                                      failure: { error in
                                                        self.reportError(error)
        })
    }

}
