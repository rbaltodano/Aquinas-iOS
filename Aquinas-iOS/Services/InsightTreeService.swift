//
//  InsightTreeService.swift
//  Aquinas-iOS
//

import Foundation
import SwiftUI

struct PersistedInsightTree: Equatable {
    let conversationID: UUID
    let embeddingModel: String
    let embeddingVersion: Int
    let nodes: [PersistedInsightTreeNode]
    let edges: [PersistedInsightTreeEdge]
}

struct PersistedInsightTreeNode: Identifiable, Equatable {
    let id: UUID
    let label: String
    let summary: String
    let needsGeneratedLabel: Bool
    let originNodeID: UUID?
    let insights: [PersistedInsightTreeInsight]
}

struct PersistedInsightTreeInsight: Identifiable, Equatable {
    let id: UUID
    let title: String
    let definition: String
    let relatedness: Double
    let distance: Double
    let sourceType: String
    let sourceResponseID: UUID?
    let sourceBranchID: UUID?
    let evidenceExcerpt: String
    let extractionRole: String?
}

struct PersistedInsightTreeEdge: Identifiable, Equatable {
    let id: UUID
    let fromNodeID: UUID
    let toNodeID: UUID
    let relatedness: Double
    let distance: Double
    let isStrongExtra: Bool
}

struct InsightTreeAnalysisResult: Equatable {
    let status: String
    let analysisID: UUID?
    let mutationID: UUID?
    let addedInsightIDs: [UUID]
    let addedNodeIDs: [UUID]
    let tree: PersistedInsightTree

    var didMutate: Bool {
        status == "updated"
            && (!addedInsightIDs.isEmpty || !addedNodeIDs.isEmpty)
    }
}

protocol InsightTreeService {
    func tree(for conversationID: UUID) async throws -> PersistedInsightTree
    func analyzeResponse(
        conversationID: UUID,
        responseID: UUID,
        branchID: UUID,
        question: String,
        response: String
    ) async throws -> InsightTreeAnalysisResult
    func save(
        _ concept: ConceptDefinition,
        to conversationID: UUID,
        suggestedNodeLabel: String?
    ) async throws
    func remove(insightID: UUID, from conversationID: UUID) async throws
    func labelNode(
        nodeID: UUID,
        in conversationID: UUID,
        label: String
    ) async throws
}

struct BackendInsightTreeService: InsightTreeService {
    private let baseURL: URL
    private let session: URLSession

    init(
        baseURL: URL = AquinasBackendConfiguration.defaultBaseURL,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.session = session
    }

    func tree(for conversationID: UUID) async throws -> PersistedInsightTree {
        let response: TreeSnapshotResponse = try await request(
            path: "insight-tree/\(conversationID.uuidString)",
            method: "GET"
        )
        return try response.domainValue
    }

    func analyzeResponse(
        conversationID: UUID,
        responseID: UUID,
        branchID: UUID,
        question: String,
        response: String
    ) async throws -> InsightTreeAnalysisResult {
        let result: ResponseTreeAnalysisResponse = try await request(
            path: "insight-tree/\(conversationID.uuidString)/responses/\(responseID.uuidString)/analyze",
            method: "POST",
            body: ResponseTreeAnalysisRequest(
                branchID: branchID.uuidString,
                question: question,
                response: response
            )
        )
        return try result.domainValue
    }

    func save(
        _ concept: ConceptDefinition,
        to conversationID: UUID,
        suggestedNodeLabel: String?
    ) async throws {
        let _: TreeAssignmentResponse = try await request(
            path: "insight-tree/\(conversationID.uuidString)/insights",
            method: "POST",
            body: TreeAssignmentRequest(
                insight: TreeInsightRequest(
                    id: concept.id.uuidString,
                    title: concept.word,
                    definition: concept.meaning
                ),
                suggestedNodeLabel: suggestedNodeLabel
            )
        )
    }

    func remove(insightID: UUID, from conversationID: UUID) async throws {
        let _: TreeSnapshotResponse = try await request(
            path: "insight-tree/\(conversationID.uuidString)/insights/\(insightID.uuidString)",
            method: "DELETE"
        )
    }

    func labelNode(
        nodeID: UUID,
        in conversationID: UUID,
        label: String
    ) async throws {
        let _: TreeSnapshotResponse = try await request(
            path: "insight-tree/\(conversationID.uuidString)/nodes/\(nodeID.uuidString)/label",
            method: "POST",
            body: TreeNodeLabelRequest(label: label)
        )
    }

    private func request<Response: Decodable>(
        path: String,
        method: String
    ) async throws -> Response {
        try await request(path: path, method: method, body: Optional<EmptyBody>.none)
    }

    private func request<Body: Encodable, Response: Decodable>(
        path: String,
        method: String,
        body: Body?
    ) async throws -> Response {
        let endpoint = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: endpoint)
        request.httpMethod = method
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw InsightTreeServiceError.invalidResponse
        }
        guard 200..<300 ~= httpResponse.statusCode else {
            throw InsightTreeServiceError.httpFailure(statusCode: httpResponse.statusCode)
        }
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw InsightTreeServiceError.invalidPayload(error)
        }
    }
}

private struct EmptyBody: Encodable {}

private struct TreeAssignmentRequest: Encodable {
    let insight: TreeInsightRequest
    let suggestedNodeLabel: String?

    enum CodingKeys: String, CodingKey {
        case insight
        case suggestedNodeLabel = "suggested_node_label"
    }
}

private struct TreeInsightRequest: Encodable {
    let id: String
    let title: String
    let definition: String
}

private struct TreeNodeLabelRequest: Encodable {
    let label: String
}

private struct ResponseTreeAnalysisRequest: Encodable {
    let branchID: String
    let question: String
    let response: String

    enum CodingKeys: String, CodingKey {
        case branchID = "branch_id"
        case question
        case response
    }
}

private struct ResponseTreeAnalysisResponse: Decodable {
    let status: String
    let analysisID: String?
    let mutationID: String?
    let addedInsightIDs: [String]
    let addedNodeIDs: [String]
    let tree: TreeSnapshotResponse

    enum CodingKeys: String, CodingKey {
        case status
        case analysisID = "analysis_id"
        case mutationID = "mutation_id"
        case addedInsightIDs = "added_insight_ids"
        case addedNodeIDs = "added_node_ids"
        case tree
    }

    var domainValue: InsightTreeAnalysisResult {
        get throws {
            let insightIDs = try addedInsightIDs.map {
                guard let id = UUID(uuidString: $0) else {
                    throw InsightTreeServiceError.invalidIdentifier
                }
                return id
            }
            let nodeIDs = try addedNodeIDs.map {
                guard let id = UUID(uuidString: $0) else {
                    throw InsightTreeServiceError.invalidIdentifier
                }
                return id
            }
            return InsightTreeAnalysisResult(
                status: status,
                analysisID: try optionalUUID(analysisID),
                mutationID: try optionalUUID(mutationID),
                addedInsightIDs: insightIDs,
                addedNodeIDs: nodeIDs,
                tree: try tree.domainValue
            )
        }
    }
}

private struct TreeAssignmentResponse: Decodable {
    let conversationID: String

    enum CodingKeys: String, CodingKey {
        case conversationID = "conversation_id"
    }
}

private struct TreeSnapshotResponse: Decodable {
    let conversationID: String
    let embeddingModel: String
    let embeddingVersion: Int
    let nodes: [TreeNodeResponse]
    let edges: [TreeEdgeResponse]

    enum CodingKeys: String, CodingKey {
        case conversationID = "conversation_id"
        case embeddingModel = "embedding_model"
        case embeddingVersion = "embedding_version"
        case nodes
        case edges
    }

    var domainValue: PersistedInsightTree {
        get throws {
            guard let conversationID = UUID(uuidString: conversationID) else {
                throw InsightTreeServiceError.invalidIdentifier
            }
            let decodedNodes = try nodes.map { try $0.domainValue }
            let savedTitleKeys = Set(
                decodedNodes
                    .flatMap(\.insights)
                    .filter { $0.sourceType == "saved_definition" }
                    .map { Self.canonicalTitleKey($0.title) }
            )
            let reconciledNodes = decodedNodes.map { node in
                PersistedInsightTreeNode(
                    id: node.id,
                    label: node.label,
                    summary: node.summary,
                    needsGeneratedLabel: node.needsGeneratedLabel,
                    originNodeID: node.originNodeID,
                    insights: node.insights.filter { insight in
                        insight.sourceType != "automatic_response"
                            || !savedTitleKeys.contains(
                                Self.canonicalTitleKey(insight.title)
                            )
                    }
                )
            }
            return PersistedInsightTree(
                conversationID: conversationID,
                embeddingModel: embeddingModel,
                embeddingVersion: embeddingVersion,
                nodes: reconciledNodes,
                edges: try edges.map { try $0.domainValue }
            )
        }
    }

    private static func canonicalTitleKey(_ title: String) -> String {
        var key = title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .trimmingCharacters(in: .punctuationCharacters)
        for suffix in [" defined", " definition"] where key.hasSuffix(suffix) {
            key.removeLast(suffix.count)
            break
        }
        return key.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct TreeNodeResponse: Decodable {
    let id: String
    let label: String
    let summary: String
    let needsGeneratedLabel: Bool
    let originNodeID: String?
    let insights: [TreeInsightResponse]

    enum CodingKeys: String, CodingKey {
        case id
        case label
        case summary
        case needsGeneratedLabel = "needs_generated_label"
        case originNodeID = "origin_node_id"
        case insights
    }

    var domainValue: PersistedInsightTreeNode {
        get throws {
            guard let id = UUID(uuidString: id) else {
                throw InsightTreeServiceError.invalidIdentifier
            }
            return PersistedInsightTreeNode(
                id: id,
                label: label,
                summary: summary,
                needsGeneratedLabel: needsGeneratedLabel,
                originNodeID: try optionalUUID(originNodeID),
                insights: try insights.map { try $0.domainValue }
            )
        }
    }
}

private struct TreeInsightResponse: Decodable {
    let id: String
    let title: String
    let definition: String
    let relatedness: Double
    let distance: Double
    let sourceType: String
    let sourceResponseID: String?
    let sourceBranchID: String?
    let evidenceExcerpt: String
    let extractionRole: String?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case definition
        case relatedness
        case distance
        case sourceType = "source_type"
        case sourceResponseID = "source_response_id"
        case sourceBranchID = "source_branch_id"
        case evidenceExcerpt = "evidence_excerpt"
        case extractionRole = "extraction_role"
    }

    var domainValue: PersistedInsightTreeInsight {
        get throws {
            guard let id = UUID(uuidString: id) else {
                throw InsightTreeServiceError.invalidIdentifier
            }
            return PersistedInsightTreeInsight(
                id: id,
                title: title,
                definition: definition,
                relatedness: relatedness,
                distance: distance,
                sourceType: sourceType,
                sourceResponseID: try optionalUUID(sourceResponseID),
                sourceBranchID: try optionalUUID(sourceBranchID),
                evidenceExcerpt: evidenceExcerpt,
                extractionRole: extractionRole
            )
        }
    }
}

private struct TreeEdgeResponse: Decodable {
    let id: String
    let fromNodeID: String
    let toNodeID: String
    let relatedness: Double
    let distance: Double
    let isStrongExtra: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case fromNodeID = "from_node_id"
        case toNodeID = "to_node_id"
        case relatedness
        case distance
        case isStrongExtra = "is_strong_extra"
    }

    var domainValue: PersistedInsightTreeEdge {
        get throws {
            guard let id = UUID(uuidString: id),
                  let fromNodeID = UUID(uuidString: fromNodeID),
                  let toNodeID = UUID(uuidString: toNodeID) else {
                throw InsightTreeServiceError.invalidIdentifier
            }
            return PersistedInsightTreeEdge(
                id: id,
                fromNodeID: fromNodeID,
                toNodeID: toNodeID,
                relatedness: relatedness,
                distance: distance,
                isStrongExtra: isStrongExtra
            )
        }
    }
}

private func optionalUUID(_ value: String?) throws -> UUID? {
    guard let value else { return nil }
    guard let id = UUID(uuidString: value) else {
        throw InsightTreeServiceError.invalidIdentifier
    }
    return id
}

private enum InsightTreeServiceError: Error {
    case invalidResponse
    case httpFailure(statusCode: Int)
    case invalidPayload(Error)
    case invalidIdentifier
}

private let defaultInsightTreeService: InsightTreeService = BackendInsightTreeService()

extension EnvironmentValues {
    @Entry var insightTreeService: InsightTreeService = defaultInsightTreeService
}
