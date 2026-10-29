// Compile with ReaderCore.swift. Receives a private connection JSON on stdin;
// prints counts and status only, never the profile, password, or response body.
import Foundation

@main
struct VerifyConnection {
    struct Input: Decodable {
        let localAddress: String?
        let remoteAddress: String
        let username: String
        let password: String
        let instanceID: String?
    }
    static func main() async throws {
        let input = try JSONDecoder().decode(Input.self, from: FileHandle.standardInput.readDataToEndOfFile())
        let profile = ServerProfile(localAddress: input.localAddress ?? "", remoteAddress: input.remoteAddress,
            username: input.username, instanceID: input.instanceID)
        let (api, status) = try await ReaderAPI.connect(profile: profile, password: input.password)
        let library: LibraryResponse = try await api.get("/v1/library")
        guard let first = library.items.first else { throw ReaderError.unavailable(404) }
        let books: BooksResponse = try await api.get("/v1/series/\(try Endpoint.identifier(first.id))")
        guard let firstBook = books.books.first else { throw ReaderError.unavailable(404) }
        let book: ReaderBook = try await api.get("/v1/books/\(try Endpoint.identifier(firstBook.id))")
        let image = try await api.data("/v1/books/\(try Endpoint.identifier(book.id))/pages/0")
        guard image.count > 100 else { throw ReaderError.unavailable(415) }
        print("Swift live API OK: readOnly=\(status.readOnly), series=\(library.items.count), books=\(books.books.count), pages=\(book.pageCount), pageBytes=\(image.count)")
    }
}
