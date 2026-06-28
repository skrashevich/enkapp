import SwiftUI
import Observation

struct TeamManagementView: View {
    @Bindable var model: EncounterViewModel
    @State private var joinTeamName = ""
    @State private var inviteLogin = ""
    @State private var renameText = ""
    @State private var siteText = ""
    @State private var forumText = ""
    @State private var confirmLeave = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                headerSection
                statusSection

                if !model.hasStoredSession {
                    loggedOutSection
                } else {
                    invitationsSection
                    if model.currentTeamID != nil {
                        if model.teamManagementInfo?.canManageTeam == true {
                            teamEditorSection
                            outgoingInvitationsSection
                        }
                    } else {
                        joinRequestSection
                    }
                }
            }
            .padding()
        }
        .background(GameTheme.background)
        .refreshable {
            await model.refreshTeam()
        }
        .task {
            guard model.hasStoredSession else { return }
            if model.myTeams.isEmpty && model.teamInvitations.isEmpty && model.teamManagementInfo == nil {
                await model.refreshTeam()
            }
        }
        .onChange(of: model.currentTeamID) {
            syncDraftFields()
        }
        .onChange(of: model.currentTeamName) {
            syncDraftFields()
        }
        .confirmationDialog(
            "Выйти из команды?",
            isPresented: $confirmLeave,
            titleVisibility: .visible
        ) {
            Button("Выйти из команды", role: .destructive) {
                Task { await model.leaveCurrentTeam() }
            }
            Button("Отмена", role: .cancel) {}
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(model.currentTeamName.isEmpty ? "Команда" : model.currentTeamName)
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(GameTheme.text)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                    Text(model.hasStoredSession ? model.settings.domain : "Требуется вход")
                        .font(.subheadline)
                        .foregroundStyle(GameTheme.muted)
                }
                Spacer()
                Button {
                    Task { await model.refreshTeam() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(GameTheme.sectionHeader)
                        .frame(width: 44, height: 44)
                        .background(GameTheme.inputBackground, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .disabled(model.isBusy || !model.hasStoredSession)
                .accessibilityLabel("Обновить команду")
            }

            HStack(spacing: 10) {
                DashboardMetric(
                    title: "Команды",
                    value: "\(model.myTeams.count)",
                    systemImage: "person.2.fill",
                    tint: GameTheme.accent
                )
                DashboardMetric(
                    title: "Входящие",
                    value: "\(model.teamInvitations.count)",
                    systemImage: "envelope.fill",
                    tint: .orange
                )
                DashboardMetric(
                    title: "Исходящие",
                    value: "\(model.teamManagementInfo?.pendingInvitations.count ?? 0)",
                    systemImage: "paperplane.fill",
                    tint: GameTheme.bonusTitle
                )
            }
        }
        .sectionPanel()
    }

    @ViewBuilder
    private var statusSection: some View {
        if !model.statusMessage.isEmpty {
            HStack(spacing: 10) {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(GameTheme.sectionHeader)
                Text(model.statusMessage)
                    .font(.subheadline)
                    .foregroundStyle(GameTheme.text)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(GameTheme.inputBackground, in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private var loggedOutSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ContentUnavailableView {
                Label("Войдите в аккаунт", systemImage: "person.crop.circle")
            } description: {
                Text("После входа здесь появятся приглашения и управление вашей командой.")
            }
            .foregroundStyle(GameTheme.text, GameTheme.muted)

            NavigationLink {
                SettingsView(model: model)
            } label: {
                Label("Открыть настройки", systemImage: "gearshape")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderedProminent)
            .tint(GameTheme.accent)
        }
        .sectionPanel()
    }

    @ViewBuilder
    private var invitationsSection: some View {
        if !model.teamInvitations.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle("Входящие приглашения")
                ForEach(model.teamInvitations) { invitation in
                    TeamInvitationRow(
                        invitation: invitation,
                        accept: { Task { await model.acceptTeamInvitation(invitation) } },
                        reject: { Task { await model.rejectTeamInvitation(invitation) } }
                    )
                }
            }
            .sectionPanel()
        }
    }

    private var teamEditorSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle("Управление")

            TeamTextActionRow(
                title: "Название",
                systemImage: "textformat",
                placeholder: "Название команды",
                text: $renameText,
                buttonTitle: "Сохранить",
                isDisabled: model.isBusy
            ) {
                Task { await model.renameCurrentTeam(renameText) }
            }

            TeamTextActionRow(
                title: "Сайт",
                systemImage: "globe",
                placeholder: "https://example.com",
                text: $siteText,
                buttonTitle: "Обновить",
                isDisabled: model.isBusy
            ) {
                Task { await model.updateCurrentTeamSite(siteText) }
            }

            TeamTextActionRow(
                title: "Форум",
                systemImage: "bubble.left.and.bubble.right",
                placeholder: "Ссылка на форум",
                text: $forumText,
                buttonTitle: "Обновить",
                isDisabled: model.isBusy
            ) {
                Task { await model.updateCurrentTeamForum(forumText) }
            }

            TeamTextActionRow(
                title: "Пригласить",
                systemImage: "person.badge.plus",
                placeholder: "Логин игрока",
                text: $inviteLogin,
                buttonTitle: "Отправить",
                isDisabled: model.isBusy
            ) {
                Task {
                    await model.inviteTeamMember(login: inviteLogin)
                    inviteLogin = ""
                }
            }

            if model.teamManagementInfo?.canLeave == true {
                Button(role: .destructive) {
                    confirmLeave = true
                } label: {
                    Label("Выйти из команды", systemImage: "rectangle.portrait.and.arrow.right")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
                .tint(.orange)
                .disabled(model.isBusy)
            }
        }
        .sectionPanel()
    }

    @ViewBuilder
    private var outgoingInvitationsSection: some View {
        let invitations = model.teamManagementInfo?.pendingInvitations ?? []
        if !invitations.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle("Отправленные приглашения")
                ForEach(invitations) { invitation in
                    HStack(spacing: 12) {
                        Image(systemName: "person.crop.circle.badge.clock")
                            .foregroundStyle(GameTheme.bonusTitle)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(invitation.login.isEmpty ? "User #\(invitation.userID)" : invitation.login)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(GameTheme.text)
                            Text(verbatim: "ID \(invitation.userID)")
                                .font(.caption)
                                .foregroundStyle(GameTheme.muted)
                        }
                        Spacer()
                        Button(role: .destructive) {
                            Task { await model.removeTeamInvitation(invitation) }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.orange)
                        .disabled(model.isBusy)
                        .accessibilityLabel("Отозвать приглашение")
                    }
                    .padding(12)
                    .background(GameTheme.inputBackground, in: RoundedRectangle(cornerRadius: 10))
                }
            }
            .sectionPanel()
        }
    }

    private var joinRequestSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle("Вступить в команду")
            TeamTextActionRow(
                title: "Заявка",
                systemImage: "person.badge.plus",
                placeholder: "Название команды",
                text: $joinTeamName,
                buttonTitle: "Отправить",
                isDisabled: model.isBusy
            ) {
                Task {
                    await model.requestTeamMembership(joinTeamName)
                    joinTeamName = ""
                }
            }
        }
        .sectionPanel()
    }

    private func syncDraftFields() {
        renameText = model.currentTeamName
    }
}

private struct TeamInvitationRow: View {
    let invitation: TeamInvitation
    let accept: () -> Void
    let reject: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "envelope.open.fill")
                    .foregroundStyle(.orange)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 3) {
                    Text(invitation.name.isEmpty ? "Команда #\(invitation.teamID)" : invitation.name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(GameTheme.text)
                    Text(verbatim: "#\(invitation.teamID)")
                        .font(.caption)
                        .foregroundStyle(GameTheme.muted)
                }
                Spacer()
            }
            HStack(spacing: 10) {
                Button(action: accept) {
                    Label("Принять", systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(GameTheme.accent)

                Button(role: .destructive, action: reject) {
                    Label("Отклонить", systemImage: "xmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.orange)
            }
        }
        .padding(12)
        .background(GameTheme.inputBackground, in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct TeamTextActionRow: View {
    let title: String
    let systemImage: String
    let placeholder: String
    @Binding var text: String
    let buttonTitle: String
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(GameTheme.sectionHeader)

            HStack(spacing: 8) {
                TextField(placeholder, text: $text)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 12)
                    .frame(minHeight: 42)
                    .background(GameTheme.inputBackground, in: RoundedRectangle(cornerRadius: 10))
                    .foregroundStyle(GameTheme.text)
                    .tint(GameTheme.accent)

                Button(buttonTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .tint(GameTheme.accent)
                    .disabled(isDisabled)
            }
        }
    }
}
