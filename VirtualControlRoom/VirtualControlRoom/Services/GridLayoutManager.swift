import Foundation
import SwiftUI
import RealityKit

/// Manages grid layout positioning and scaling for multiple VNC windows in groups
@MainActor
class GridLayoutManager: ObservableObject {
    static let shared = GridLayoutManager()
    
    // Window tracking for groups
    @Published var activeGroupWindows: [String: [String]] = [:] // groupID -> [windowIDs]
    
    // Layout configuration
    private let baseWindowSize = CGSize(width: 1200, height: 800)
    private let windowSpacing: Float = 0.2 // meters between windows
    private let gridDepth: Float = -2.0 // distance from user
    
    private init() {}
    
    // MARK: - Grid Layout Calculation
    
    /// Calculate grid dimensions from layout string
    func getGridDimensions(from layoutType: String) -> (rows: Int, columns: Int) {
        switch layoutType {
        case "1x1":
            return (1, 1)
        case "2x1":
            return (1, 2)
        case "3x1":
            return (1, 3)
        case "2x2":
            return (2, 2)
        case "3x2":
            return (2, 3)
        case "3x3":
            return (3, 3)
        default:
            // Auto-calculate optimal grid for connection count
            let count = Int(layoutType.prefix(1)) ?? 1
            return calculateOptimalGrid(for: count)
        }
    }
    
    /// Calculate optimal grid layout for a given number of connections
    private func calculateOptimalGrid(for count: Int) -> (rows: Int, columns: Int) {
        switch count {
        case 0, 1:
            return (1, 1)
        case 2:
            return (1, 2)
        case 3:
            return (1, 3)
        case 4:
            return (2, 2)
        case 5, 6:
            return (2, 3)
        case 7, 8, 9:
            return (3, 3)
        default:
            // For larger numbers, prefer wider layouts
            let cols = Int(ceil(sqrt(Double(count))))
            let rows = Int(ceil(Double(count) / Double(cols)))
            return (rows, cols)
        }
    }
    
    /// Calculate window positions for a grid layout
    func calculateGridPositions(layoutType: String, connectionCount: Int) -> [GridPosition] {
        let (rows, cols) = getGridDimensions(from: layoutType)
        var positions: [GridPosition] = []
        
        // Calculate scaling factor based on grid size
        let scaleFactor = calculateScaleFactor(rows: rows, columns: cols)
        let windowSize = CGSize(
            width: baseWindowSize.width * scaleFactor,
            height: baseWindowSize.height * scaleFactor
        )
        
        // Calculate spacing between windows
        let horizontalSpacing = windowSpacing * Float(scaleFactor)
        let verticalSpacing = windowSpacing * Float(scaleFactor)
        
        // Calculate total grid size to center it
        let totalWidth = Float(cols - 1) * horizontalSpacing
        let totalHeight = Float(rows - 1) * verticalSpacing
        
        // Starting position (top-left of grid, centered)
        let startX = -totalWidth / 2.0
        let startY = totalHeight / 2.0
        
        // Generate positions for each grid cell
        var positionIndex = 0
        for row in 0..<rows {
            for col in 0..<cols {
                guard positionIndex < connectionCount else { break }
                
                let x = startX + Float(col) * horizontalSpacing
                let y = startY - Float(row) * verticalSpacing
                let z = gridDepth
                
                positions.append(GridPosition(
                    index: positionIndex,
                    row: row,
                    column: col,
                    position: SIMD3<Float>(x, y, z),
                    size: windowSize,
                    scaleFactor: scaleFactor
                ))
                
                positionIndex += 1
            }
        }
        
        return positions
    }
    
    /// Calculate appropriate scale factor for grid size
    private func calculateScaleFactor(rows: Int, columns: Int) -> CGFloat {
        let totalCells = rows * columns
        
        switch totalCells {
        case 1:
            return 1.0 // Full size for single window
        case 2:
            return 0.8 // Slightly smaller for 2 windows
        case 3, 4:
            return 0.65 // Medium size for 3-4 windows
        case 5, 6:
            return 0.55 // Smaller for 5-6 windows
        case 7, 8, 9:
            return 0.45 // Small for 7-9 windows
        default:
            return 0.35 // Very small for larger grids
        }
    }
    
    // MARK: - Window Management
    
    /// Generate unique window ID for group connection
    func generateGroupWindowID(groupID: String, connectionID: String) -> (windowID: String, windowValue: GroupWindowValue) {
        let windowID = "vnc-group-window"
        let windowValue = GroupWindowValue(
            groupID: groupID,
            connectionID: connectionID,
            isGroupWindow: true
        )
        return (windowID, windowValue)
    }
    
    /// Launch group windows with grid positioning
    func launchGroupWindows(
        groupID: String,
        connections: [ConnectionProfile],
        layoutType: String,
        openWindow: @escaping (String, GroupWindowValue) -> Void
    ) {
        print("🏗️ GridLayoutManager: Launching \(connections.count) windows in \(layoutType) layout")
        
        let positions = calculateGridPositions(layoutType: layoutType, connectionCount: connections.count)
        var windowIDs: [String] = []
        
        // Launch windows with calculated positions
        for (index, connection) in connections.enumerated() {
            guard index < positions.count,
                  let connectionID = connection.id?.uuidString else { continue }
            
            let position = positions[index]
            let (windowID, windowValue) = generateGroupWindowID(groupID: groupID, connectionID: connectionID)
            
            // Add position information to window value
            var windowValueWithPosition = windowValue
            windowValueWithPosition.gridPosition = position
            
            windowIDs.append("\(windowID)-\(connectionID)")
            
            print("🪟 Opening group window at position (\(position.position.x), \(position.position.y), \(position.position.z)) scale: \(position.scaleFactor)")
            
            // Open the window with positioning information
            openWindow(windowID, windowValueWithPosition)
        }
        
        // Track active windows for this group
        activeGroupWindows[groupID] = windowIDs
        
        print("✅ GridLayoutManager: Launched \(windowIDs.count) group windows for group \(groupID)")
    }
    
    /// Close all windows for a group
    func closeGroupWindows(groupID: String) {
        guard let windowIDs = activeGroupWindows[groupID] else {
            print("⚠️ No active windows found for group \(groupID)")
            return
        }
        
        print("🗂️ GridLayoutManager: Closing \(windowIDs.count) windows for group \(groupID)")
        
        // Note: In visionOS, we can't directly close windows programmatically
        // Windows are closed by the system or user interaction
        // We just clean up our tracking
        
        activeGroupWindows.removeValue(forKey: groupID)
        print("✅ GridLayoutManager: Cleaned up window tracking for group \(groupID)")
    }
    
    /// Check if a group has active windows
    func hasActiveWindows(groupID: String) -> Bool {
        return activeGroupWindows[groupID]?.isEmpty == false
    }
    
    /// Get window count for a group
    func getWindowCount(groupID: String) -> Int {
        return activeGroupWindows[groupID]?.count ?? 0
    }
}

// MARK: - Supporting Types

/// Represents a position in the grid layout
struct GridPosition {
    let index: Int
    let row: Int
    let column: Int
    let position: SIMD3<Float> // 3D position in visionOS space
    let size: CGSize
    let scaleFactor: CGFloat
}

/// Window value passed to visionOS window system for group windows
struct GroupWindowValue: Hashable, Codable {
    let groupID: String
    let connectionID: String
    let isGroupWindow: Bool
    var gridPosition: GridPosition?
    
    // Codable conformance - exclude gridPosition since it's not easily codable
    enum CodingKeys: String, CodingKey {
        case groupID
        case connectionID  
        case isGroupWindow
    }
    
    // Hashable conformance
    func hash(into hasher: inout Hasher) {
        hasher.combine(groupID)
        hasher.combine(connectionID)
        hasher.combine(isGroupWindow)
    }
    
    static func == (lhs: GroupWindowValue, rhs: GroupWindowValue) -> Bool {
        return lhs.groupID == rhs.groupID &&
               lhs.connectionID == rhs.connectionID &&
               lhs.isGroupWindow == rhs.isGroupWindow
    }
}