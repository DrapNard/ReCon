import WidgetKit
import SwiftUI

@main
struct ReConWidgetBundle: WidgetBundle {
    var body: some Widget {
        ReConWidget()
        ReConLatestSessionWidget()
        ReConOnlineFriendsWidget()
    }
}
