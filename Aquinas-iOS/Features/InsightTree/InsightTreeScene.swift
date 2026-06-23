//
//  InsightTreeScene.swift
//  Aquinas-iOS
//

import SpriteKit
import SwiftUI
import UIKit

// MARK: - Insight Tree Scene

final class InsightTreeScene: SKScene {
    var nodeSprites: [UUID: SKNode] = [:]
    var edgeSprites: [UUID: SKShapeNode] = [:]
    var onNodeTapped: ((NodeModel) -> Void)?
    var onSuggestConnection: ((EdgeModel) -> Void)?

    private var nodes: [NodeModel] = []
    private var edges: [EdgeModel] = []
    private let cameraNode = SKCameraNode()
    private var selectedEdgeButton: SKNode?

    override func didMove(to view: SKView) {
        backgroundColor = UIColor(AquinasTheme.Colors.canvas)
        if camera == nil {
            camera = cameraNode
            addChild(cameraNode)
        }
        setupGestures()
    }

    func render(nodes: [NodeModel], edges: [EdgeModel], animated: Bool) {
        self.nodes = nodes
        self.edges = edges
        removeAllChildren()
        nodeSprites.removeAll()
        edgeSprites.removeAll()
        addChild(cameraNode)
        camera = cameraNode

        for edge in edges {
            guard let from = nodes.first(where: { $0.id == edge.fromNodeID }),
                  let to = nodes.first(where: { $0.id == edge.toNodeID }) else {
                continue
            }
            let shape = makeEdge(edge, from: from.position, to: to.position)
            edgeSprites[edge.id] = shape
            addChild(shape)
        }

        for node in nodes {
            let sprite = makeNode(node)
            nodeSprites[node.id] = sprite
            addChild(sprite)
            if animated {
                sprite.setScale(0.92)
                sprite.alpha = 0
                sprite.run(.group([
                    .fadeIn(withDuration: 0.28),
                    .scale(to: 1.0, duration: 0.32)
                ]))
            }
        }

        updateZoomDependentLabels()
    }

    func setupGestures() {
        guard let view else { return }
        if view.gestureRecognizers?.contains(where: { $0.name == "InsightTreePan" }) != true {
            let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan))
            pan.name = "InsightTreePan"
            view.addGestureRecognizer(pan)
        }
        if view.gestureRecognizers?.contains(where: { $0.name == "InsightTreePinch" }) != true {
            let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch))
            pinch.name = "InsightTreePinch"
            view.addGestureRecognizer(pinch)
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        cancelNodeAnimations()
        super.touchesBegan(touches, with: event)
    }

    private func cancelNodeAnimations() {
        for (_, sprite) in nodeSprites {
            sprite.removeAllActions()
            sprite.alpha = 1
            sprite.setScale(1)
        }
    }

    @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
        if recognizer.state == .began { cancelNodeAnimations() }
        guard let view, let camera else { return }
        dismissSuggestButton()
        let translation = recognizer.translation(in: view)
        camera.position.x -= translation.x * camera.xScale
        camera.position.y += translation.y * camera.yScale
        recognizer.setTranslation(.zero, in: view)
    }

    @objc private func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
        guard let camera else { return }
        dismissSuggestButton()
        let nextScale = max(0.3, min(3.0, camera.xScale / recognizer.scale))
        camera.setScale(nextScale)
        recognizer.scale = 1
        updateZoomDependentLabels()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)
        let touchedNodes = nodes(at: location)

        if let suggestNode = touchedNodes.first(where: { $0.name?.hasPrefix("suggest-edge:") == true }),
           let idString = suggestNode.name?.replacingOccurrences(of: "suggest-edge:", with: ""),
           let id = UUID(uuidString: idString),
           let edge = edges.first(where: { $0.id == id }) {
            dismissSuggestButton()
            onSuggestConnection?(edge)
            return
        }

        if let nodeSprite = touchedNodes.first(where: { $0.name?.hasPrefix("node:") == true }),
           let idString = nodeSprite.name?.replacingOccurrences(of: "node:", with: ""),
           let id = UUID(uuidString: idString),
           let node = nodes.first(where: { $0.id == id }) {
            onNodeTapped?(node)
            return
        }

        if let edgeSprite = touchedNodes.first(where: { $0.name?.hasPrefix("edge:") == true }),
           let idString = edgeSprite.name?.replacingOccurrences(of: "edge:", with: ""),
           let id = UUID(uuidString: idString),
           let edge = edges.first(where: { $0.id == id }) {
            showSuggestButton(for: edge)
            return
        }

        dismissSuggestButton()
    }

    private func makeNode(_ node: NodeModel) -> SKNode {
        let group = SKNode()
        group.name = "node:\(node.id.uuidString)"
        group.position = node.position
        group.zPosition = node.isSuggested ? 20 : 10

        let icon = SKLabelNode(fontNamed: "SF Pro")
        icon.text = node.isSuggested ? "⌘" : "◌"
        icon.fontSize = node.isSuggested ? 20 : 16
        icon.fontColor = UIColor(AquinasTheme.Colors.lightGreen)
        icon.verticalAlignmentMode = .center
        icon.position = CGPoint(x: 0, y: 24)
        icon.name = group.name
        group.addChild(icon)

        let label = SKLabelNode(fontNamed: "LibreBaskerville-Regular")
        label.text = node.conceptLabel
        label.fontSize = node.isSuggested ? 20 : 24
        label.fontColor = UIColor(AquinasTheme.Colors.primaryReadable)
        label.verticalAlignmentMode = .center
        label.position = .zero
        label.name = group.name
        group.addChild(label)

        let titles = SKNode()
        titles.name = "zoom-titles"
        let insightCount = max(node.insights.count, 1)
        for (index, insight) in node.insights.prefix(6).enumerated() {
            let angle = (CGFloat(index) / CGFloat(insightCount)) * (.pi * 2)
            let radius = CGFloat(120)
            let title = makeInsightTitle(insight.title)
            title.position = CGPoint(x: cos(angle) * radius, y: sin(angle) * radius)
            title.name = group.name
            titles.addChild(title)
        }
        group.addChild(titles)

        if node.isSuggested {
            let close = SKLabelNode(fontNamed: "Figtree-Bold")
            close.text = "×"
            close.fontSize = 16
            close.fontColor = UIColor(AquinasTheme.Colors.primaryReadable)
            close.position = CGPoint(x: 54, y: 32)
            close.name = group.name
            group.addChild(close)
        }

        return group
    }

    private func makeInsightTitle(_ title: String) -> SKNode {
        let group = SKNode()
        let icon = SKLabelNode(fontNamed: "SF Pro")
        icon.text = "▰"
        icon.fontSize = 8
        icon.fontColor = UIColor(AquinasTheme.Colors.lightGreen)
        icon.verticalAlignmentMode = .center
        icon.position = CGPoint(x: -12, y: 0)
        group.addChild(icon)

        let label = SKLabelNode(fontNamed: "Figtree-Bold")
        label.text = title
        label.fontSize = 11
        label.fontColor = UIColor(AquinasTheme.Colors.lightGreen)
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .left
        group.addChild(label)
        return group
    }

    private func makeEdge(_ edge: EdgeModel, from: CGPoint, to: CGPoint) -> SKShapeNode {
        let path = CGMutablePath()
        path.move(to: from)
        path.addLine(to: to)
        let renderedPath = edge.isSuggested
            ? path.copy(dashingWithPhase: 0, lengths: [6, 4])
            : path
        let shape = SKShapeNode(path: renderedPath)
        shape.name = "edge:\(edge.id.uuidString)"
        shape.strokeColor = UIColor(AquinasTheme.Colors.divider)
        shape.lineWidth = 1
        shape.alpha = edge.isSuggested ? 0.55 : 0.9
        shape.zPosition = 1
        return shape
    }

    private func showSuggestButton(for edge: EdgeModel) {
        dismissSuggestButton()
        guard edge.showSuggestButton,
              let from = nodes.first(where: { $0.id == edge.fromNodeID }),
              let to = nodes.first(where: { $0.id == edge.toNodeID }) else {
            return
        }

        let midpoint = CGPoint(x: (from.position.x + to.position.x) / 2, y: (from.position.y + to.position.y) / 2)
        let group = SKNode()
        group.name = "suggest-edge:\(edge.id.uuidString)"
        group.position = midpoint
        group.zPosition = 30

        let pill = SKShapeNode(rectOf: CGSize(width: 148, height: 32), cornerRadius: 16)
        pill.fillColor = UIColor(AquinasTheme.Colors.surface)
        pill.strokeColor = UIColor(AquinasTheme.Colors.controlBorder)
        pill.lineWidth = 1
        pill.name = group.name
        group.addChild(pill)

        let label = SKLabelNode(fontNamed: "Figtree-Bold")
        label.text = "Suggest Connection"
        label.fontSize = 11
        label.fontColor = UIColor(AquinasTheme.Colors.primaryReadable)
        label.verticalAlignmentMode = .center
        label.name = group.name
        group.addChild(label)

        group.alpha = 0
        addChild(group)
        selectedEdgeButton = group
        group.run(.fadeIn(withDuration: 0.18))
    }

    private func dismissSuggestButton() {
        selectedEdgeButton?.removeFromParent()
        selectedEdgeButton = nil
    }

    private func updateZoomDependentLabels() {
        let shouldShowTitles = (camera?.xScale ?? 1) < 0.72
        for node in nodeSprites.values {
            node.childNode(withName: "zoom-titles")?.isHidden = !shouldShowTitles
        }
    }
}
