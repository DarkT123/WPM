import Foundation

enum EdgeAPIError: Error, LocalizedError {
    case badURL
    case status(Int)
    case decode(Error)
    case transport(Error)

    var errorDescription: String? {
        switch self {
        case .badURL: return "Bad backend URL"
        case .status(let s): return "Backend returned HTTP \(s)"
        case .decode(let e): return "Decode failed: \(e.localizedDescription)"
        case .transport(let e): return "Transport failed: \(e.localizedDescription)"
        }
    }
}

actor EdgeAPI {
    private var baseURL: URL
    private let session: URLSession

    init(baseURL: URL = URL(string: "http://localhost:3002")!) {
        self.baseURL = baseURL
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 5
        cfg.waitsForConnectivity = false
        self.session = URLSession(configuration: cfg)
    }

    func setBaseURL(_ url: URL) { self.baseURL = url }
    func currentBaseURL() -> URL { baseURL }

    func health() async throws -> HealthResponse {
        try await get("/api/health")
    }

    func predict(_ req: PredictRequest) async throws -> PredictResponse {
        try await post("/api/predict", body: req)
    }

    func learn(_ req: LearnRequest) async throws -> LearnResponse {
        try await post("/api/learn", body: req)
    }

    // MARK: - Internals

    private func get<T: Decodable>(_ path: String) async throws -> T {
        guard let url = URL(string: path, relativeTo: baseURL) else { throw EdgeAPIError.badURL }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        return try await send(req)
    }

    private func post<Body: Encodable, T: Decodable>(_ path: String, body: Body) async throws -> T {
        guard let url = URL(string: path, relativeTo: baseURL) else { throw EdgeAPIError.badURL }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.httpBody = try JSONEncoder().encode(body)
        return try await send(req)
    }

    private func send<T: Decodable>(_ req: URLRequest) async throws -> T {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw EdgeAPIError.transport(error)
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw EdgeAPIError.status(http.statusCode)
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw EdgeAPIError.decode(error)
        }
    }
}
