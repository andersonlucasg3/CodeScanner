//
//  ContentView.swift
//  CodeScannerTestApp
//
//  Created by Anderson Lucas C. Ramos on 08/06/20.
//  Copyright © 2020 Brasil. All rights reserved.
//

import SwiftUI
import CodeScanner

struct ContentView: View {
    var body: some View {
        CodeScannerView.init(codeTypes: [.ean13]) { (result) in
            print(result)
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
