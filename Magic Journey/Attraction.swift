import Foundation

struct Attractionss: Identifiable, Decodable {
    let id: UUID
    let name: String
    let status: String
    let parkId: String
    let externalId: String
    let lastUpdated: String
    let waitTime: Int?
    let previousWaitTime: Int?
    let type: String
    let coordinates: [Double]
    let land: String
    let description: String
    
    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case name, status, parkId, externalId, lastUpdated, waitTime, previousWaitTime, type, coordinates, land, description
    }
}
