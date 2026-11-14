import SwiftUI
import SwiftData

@Model
final class Expense {
    var kopiyky: Int
    var category: String
    var date: Date

    init(kopiyky: Int, category: String, date: Date) {
        self.kopiyky = kopiyky
        self.category = category
        self.date = date
    }
}

@main
struct ExpensesApp: App {
    var body: some Scene {
        WindowGroup { ExpenseList() }
            .modelContainer(for: Expense.self)
    }
}

func currency(_ amount: Int) -> String {
    (Decimal(amount) / 100).formatted(.currency(code: "UAH").locale(Locale(identifier: "uk_UA")))
}

struct ExpenseList: View {
    @Query(sort: \Expense.date, order: .reverse) private var expenses: [Expense]
    @State private var month = Date.now
    @State private var adding = false
    private let calendar = Calendar.current

    private var visible: [Expense] {
        expenses.filter { calendar.isDate($0.date, equalTo: month, toGranularity: .month) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Button { shift(-1) } label: { Image(systemName: "chevron.left") }
                            .accessibilityLabel("Попередній місяць")
                        Spacer()
                        Text(month.formatted(.dateTime.month(.wide).year().locale(Locale(identifier: "uk_UA"))))
                        Spacer()
                        Button { shift(1) } label: { Image(systemName: "chevron.right") }
                            .accessibilityLabel("Наступний місяць")
                    }
                    .buttonStyle(.borderless)
                    Text(currency(visible.reduce(0) { $0 + $1.kopiyky }))
                        .font(.largeTitle.bold())
                        .monospacedDigit()
                } header: { Text("Витрачено за місяць") }

                Section("Історія") {
                    if visible.isEmpty {
                        Text("За цей місяць витрат ще немає.").foregroundStyle(.secondary)
                    }
                    ForEach(visible) { item in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(item.category)
                                Text(item.date, format: .dateTime.day().month(.wide).locale(Locale(identifier: "uk_UA")))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(currency(item.kopiyky)).monospacedDigit()
                        }
                    }
                }
            }
            .navigationTitle("Витрати")
            .toolbar {
                Button { adding = true } label: { Label("Додати витрату", systemImage: "plus") }
            }
            .sheet(isPresented: $adding) {
                ExpenseForm { date in month = date }
            }
        }
    }

    private func shift(_ offset: Int) {
        guard let start = calendar.dateInterval(of: .month, for: month)?.start,
              let next = calendar.date(byAdding: .month, value: offset, to: start) else { return }
        month = next
    }
}

struct ExpenseForm: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var amount = ""
    @State private var category = "Продукти"
    @State private var date = Date.now
    @State private var saveFailed = false
    let onSave: (Date) -> Void
    private let categories = ["Продукти", "Транспорт", "Дім", "Здоров’я", "Дозвілля", "Інше"]

    private var kopiyky: Int? {
        let value = amount.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard value.wholeMatch(of: #/[0-9]{1,9}(\.[0-9]{1,2})?/#) != nil,
              let decimal = Decimal(string: value, locale: Locale(identifier: "en_US_POSIX"))
        else { return nil }
        let cents = NSDecimalNumber(decimal: decimal * 100).intValue
        return cents > 0 ? cents : nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Сума, грн") {
                    TextField("0,00", text: $amount).keyboardType(.decimalPad)
                }
                Picker("Категорія", selection: $category) {
                    ForEach(categories, id: \.self) { Text($0) }
                }
                DatePicker("Дата", selection: $date, displayedComponents: .date)
                    .environment(\.locale, Locale(identifier: "uk_UA"))
            }
            .navigationTitle("Нова витрата")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Скасувати") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Зберегти", action: save).disabled(kopiyky == nil)
                }
            }
            .alert("Не вдалося зберегти витрату", isPresented: $saveFailed) {
                Button("Гаразд") {}
            }
        }
    }

    private func save() {
        guard let kopiyky else { return }
        context.insert(Expense(kopiyky: kopiyky, category: category, date: date))
        do {
            try context.save()
            onSave(date)
            dismiss()
        } catch {
            context.rollback()
            saveFailed = true
        }
    }
}
