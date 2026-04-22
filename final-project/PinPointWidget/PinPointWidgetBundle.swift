//
//  PinPointWidgetBundle.swift
//  PinPointWidget
//
//  Created by Whitman Stewart on 4/22/26.
//

import WidgetKit
import SwiftUI

@main
struct PinPointWidgetBundle: WidgetBundle {
    var body: some Widget {
        PinPointQuickSaveWidget()
        PinPointGuideWidget()
    }
}
