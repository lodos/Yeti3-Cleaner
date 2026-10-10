import Contacts
import Foundation

struct ContactItem: Identifiable {
    let id: String
    let name: String
    let phones: [String]
    let emails: [String]
    var incomplete: Bool { name.isEmpty || (phones.isEmpty && emails.isEmpty) }
}
struct ContactReport {
    var items: [ContactItem] = []
    var groups: [[String]] = []
}
actor ContactService {
    func scan() throws -> ContactReport {
        let store = CNContactStore()
        let request = CNContactFetchRequest(keysToFetch: [CNContactIdentifierKey, CNContactGivenNameKey, CNContactFamilyNameKey, CNContactOrganizationNameKey, CNContactPhoneNumbersKey, CNContactEmailAddressesKey] as [CNKeyDescriptor])
        request.unifyResults = true
        var report = ContactReport(); var keys: [String: Set<String>] = [:]
        try store.enumerateContacts(with: request) { contact, stop in
            if Task.isCancelled { stop.pointee = true; return }
            let personal = "\(contact.givenName) \(contact.familyName)".trimmingCharacters(in: .whitespaces)
            let item = ContactItem(id: contact.identifier, name: personal.isEmpty ? contact.organizationName : personal, phones: contact.phoneNumbers.map { $0.value.stringValue }, emails: contact.emailAddresses.map { String($0.value) })
            report.items.append(item)
            for phone in item.phones {
                let normalized = SafetyPolicy.normalizedPhone(phone)
                if normalized.count >= 7 { keys["p:" + normalized, default: []].insert(item.id) }
            }
            for email in item.emails {
                let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if !normalized.isEmpty { keys["e:" + normalized, default: []].insert(item.id) }
            }
        }
        try Task.checkCancellation()
        report.groups = Array(Set(keys.values.filter { $0.count > 1 }.map { $0.sorted() })).sorted { $0[0] < $1[0] }
        return report
    }
}
