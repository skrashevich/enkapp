import SwiftUI

// MARK: - Полный текст атрибуции словаря (Track C)
//
// Дословно из docs/LICENSE-dict.md, раздел «Текст атрибуции для UI» — полная форма.
// Текст лицензий не переводить и не менять: это обязательное условие CC-BY-SA
// (OpenCorpora) и BSD-подобной лицензии Лебедева.

private let fullDictionaryAttributionText = """
Russian dictionary data: OpenCorpora (http://opencorpora.org), licensed under
Creative Commons Attribution-ShareAlike (CC BY-SA). This application includes
a modified/adapted version of the OpenCorpora word-form database, repackaged
into a binary format. The adapted database is available under the same
CC BY-SA license.

Additional dictionary data: Copyright (c) 1997-2008, Alexander I. Lebedev.
All rights reserved.

Redistribution and use in source and binary forms, with or without modification, are
permitted provided that the following conditions are met:
* Redistributions of source code must retain the above copyright notice, this list of
  conditions and the following disclaimer.
* Redistributions in binary form must reproduce the above copyright notice, this list of
  conditions and the following disclaimer in the documentation and/or other materials
  provided with the distribution.
* Modified versions must be clearly marked as such.
* The name of Alexander I. Lebedev may not be used to endorse or promote products derived
  from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS
OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR
TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE,
EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
"""

/// Под-экран с полным текстом лицензий словаря (OpenCorpora CC-BY-SA + Лебедев BSD).
/// Открывается из AnagramizerView — обязательное условие обеих лицензий: полный
/// текст уведомлений должен быть доступен пользователю.
struct AnagramizerLicenseView: View {
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    SectionTitle("Лицензии словаря")
                    Text(fullDictionaryAttributionText)
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(GameTheme.text)
                        .textSelection(.enabled)
                }
                .sectionPanel()
            }
            .padding()
        }
        .background(GameTheme.background)
        .scrollContentBackground(.hidden)
        .preferredColorScheme(.dark)
        .navigationTitle("Лицензии")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(GameTheme.background, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }
}

#Preview {
    NavigationStack {
        AnagramizerLicenseView()
    }
}
