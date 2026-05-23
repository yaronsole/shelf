import Foundation
import SwiftUI

// MARK: - MilestoneToast

struct MilestoneToast: Identifiable {
    let id = UUID()
    let message: String
}

// MARK: - MilestoneManager

@Observable
final class MilestoneManager {
    var totalLikes: Int = 0
    var totalPasses: Int = 0
    var totalReactions: Int = 0
    var pendingToast: MilestoneToast? = nil

    init() {
        totalLikes     = UserDefaults.standard.integer(forKey: "totalLikes")
        totalPasses    = UserDefaults.standard.integer(forKey: "totalPasses")
        totalReactions = UserDefaults.standard.integer(forKey: "totalReactions")
    }

    func recordLike() {
        totalLikes += 1
        totalReactions += 1
        UserDefaults.standard.set(totalLikes,     forKey: "totalLikes")
        UserDefaults.standard.set(totalReactions, forKey: "totalReactions")
        checkMilestones()
    }

    func recordPass() {
        totalPasses += 1
        totalReactions += 1
        UserDefaults.standard.set(totalPasses,    forKey: "totalPasses")
        UserDefaults.standard.set(totalReactions, forKey: "totalReactions")
        checkMilestones()
    }

    func recordReaction() {
        totalReactions += 1
        UserDefaults.standard.set(totalReactions, forKey: "totalReactions")
        checkMilestones()
    }

    func showReturnGreeting(daysSince: Int) {
        if daysSince >= 7 {
            pendingToast = MilestoneToast(message: "A week away — Shelf has been saving the good ones for you. 📚")
        } else if daysSince >= 3 {
            pendingToast = MilestoneToast(message: "You've been away! Shelf missed you. Time for some new picks.")
        } else if daysSince >= 1 {
            pendingToast = MilestoneToast(message: "Back for more? Shelf has ideas waiting.")
        }
    }

    func reset() {
        totalLikes     = 0
        totalPasses    = 0
        totalReactions = 0
        pendingToast   = nil
        UserDefaults.standard.removeObject(forKey: "totalLikes")
        UserDefaults.standard.removeObject(forKey: "totalPasses")
        UserDefaults.standard.removeObject(forKey: "totalReactions")
    }

    // MARK: - Private

    private func checkMilestones() {
        // Like milestones
        switch totalLikes {
        case 1:  pendingToast = MilestoneToast(message: "First like saved! Your wishlist is starting. 📚")
        case 5:  pendingToast = MilestoneToast(message: "5 books liked — Shelf is getting your taste. 🎯")
        case 10: pendingToast = MilestoneToast(message: "10 likes in. Shelf really knows you now. ✨")
        case 25: pendingToast = MilestoneToast(message: "25 books liked. You are a reader. 🏆")
        default: break
        }
        // First pass
        if totalPasses == 1 {
            pendingToast = MilestoneToast(message: "Passing is just as useful as liking. Shelf learns either way.")
        }
        // Reaction milestone
        if totalReactions == 10 {
            pendingToast = MilestoneToast(message: "10 reactions in — you're shaping your recommendations.")
        }
    }
}
