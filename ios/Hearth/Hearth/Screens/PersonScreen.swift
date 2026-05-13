import SwiftUI

struct PersonScreen: View {
    private let person = PeopleData.sarah
    private let photos = PeopleData.photos

    var body: some View {
        Page(spacing: 28, horizontalPadding: 48, topPadding: 28) {
            ContextStrip(
                says: "This is \(person.name), \(person.relationship.lowercased()).",
                heard: "who is this?"
            )

            personCard

            VStack(alignment: .leading, spacing: 14) {
                Eyebrow(text: "Photos with \(person.name)")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 18) {
                        ForEach(photos) { photo in
                            VStack(spacing: 10) {
                                RoundedRectangle(cornerRadius: 22)
                                    .fill(photo.tone.gradient)
                                    .frame(width: 280, height: 220)
                                    .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
                                Text(photo.caption)
                                    .font(HearthFont.serif(size: 22, weight: .medium))
                                    .tracking(-0.2)
                                    .foregroundStyle(HearthColor.ink)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                            }
                            .frame(width: 280)
                        }
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 4)
                }
            }
        }
    }

    private var personCard: some View {
        HStack(spacing: 36) {
            RoundedRectangle(cornerRadius: 28)
                .fill(person.portraitTone.gradient)
                .frame(width: 320, height: 320)
                .overlay(
                    Text(String(person.name.prefix(1)))
                        .font(HearthFont.serif(size: 140, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                )
                .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)

            VStack(alignment: .leading, spacing: 6) {
                Text("THIS IS")
                    .font(HearthFont.sans(size: 18, weight: .bold))
                    .tracking(1.6)
                    .foregroundStyle(HearthColor.inkMute)
                    .padding(.bottom, 4)
                Text(person.name)
                    .font(HearthFont.serif(size: 96, weight: .medium))
                    .tracking(-1.5)
                    .foregroundStyle(HearthColor.ink)
                Text(person.relationship)
                    .font(HearthFont.serif(size: 36, weight: .medium))
                    .foregroundStyle(HearthColor.emberDeep)
                    .padding(.top, 8)

                HStack(spacing: 18) {
                    Label {
                        Text("From \(person.from)")
                            .font(HearthFont.sans(size: 24, weight: .bold))
                            .foregroundStyle(HearthColor.inkSoft)
                    } icon: {
                        Icon(name: "map-pin", size: 22, color: HearthColor.ember)
                    }
                    Circle().fill(HearthColor.inkFaint).frame(width: 6, height: 6)
                    Label {
                        Text("\(person.age) years old")
                            .font(HearthFont.sans(size: 24, weight: .bold))
                            .foregroundStyle(HearthColor.inkSoft)
                    } icon: {
                        Icon(name: "cake", size: 22, color: HearthColor.ember)
                    }
                }
                .padding(.top, 16)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(28)
        .background(RoundedRectangle(cornerRadius: 36).fill(HearthColor.card))
        .overlay(RoundedRectangle(cornerRadius: 36).stroke(HearthColor.ember, lineWidth: 3))
    }
}
