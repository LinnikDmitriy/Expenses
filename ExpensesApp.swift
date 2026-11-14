import SwiftUI
import SwiftData

@Model
final class Expense {
    var purchaseName: String?
    var kopiyky: Int
    var category: String
    var date: Date

    init(kopiyky: Int, category: String, date: Date) {
        self.kopiyky = kopiyky
        self.category = category
        self.date = date
    }
}

@Model
final class PlannedPurchase {
    var name: String
    var createdAt: Date

    init(name: String) {
        self.name = name
        self.createdAt = .now
    }
}

@main
struct ExpensesApp: App {
    var body: some Scene {
        WindowGroup {
            TabView {
                ShoppingPlan()
                    .tabItem { Label("План покупок", systemImage: "checklist") }
                ExpenseList()
                    .tabItem { Label("Витрати", systemImage: "wallet.pass") }
            }
        }
            .modelContainer(for: [Expense.self, PlannedPurchase.self])
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
                                Text(item.purchaseName ?? item.category)
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
    @State private var date = Date.now
    @State private var saveFailed = false
    let purchase: PlannedPurchase?
    @State private var expenseName = ""
    let onSave: (Date) -> Void

    init(purchase: PlannedPurchase? = nil, onSave: @escaping (Date) -> Void) {
        self.purchase = purchase
        self.onSave = onSave
        _expenseName = State(initialValue: purchase?.name ?? "")
    }

    private var name: String {
        expenseName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

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
                Section("Що придбано") {
                    TextField("Наприклад, кава в зернах", text: $expenseName)
                }
                Section("Сума, грн") {
                    TextField("0,00", text: $amount).keyboardType(.decimalPad)
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
                    Button("Зберегти", action: save).disabled(name.isEmpty || kopiyky == nil)
                }
            }
            .alert("Не вдалося зберегти витрату", isPresented: $saveFailed) {
                Button("Гаразд") {}
            }
        }
    }

    private func save() {
        guard !name.isEmpty, let kopiyky else { return }
        let expense = Expense(kopiyky: kopiyky, category: "", date: date)
        expense.purchaseName = name
        context.insert(expense)
        if let purchase { context.delete(purchase) }
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

struct ShoppingPlan: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \PlannedPurchase.createdAt, order: .reverse) private var purchases: [PlannedPurchase]
    @State private var draft = ""
    @State private var buying: PlannedPurchase?
    @State private var saveFailed = false

    private var name: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        TextField("Що хочеш купити?", text: $draft)
                            .submitLabel(.done)
                            .onSubmit(add)
                        Button(action: add) {
                            Label("Додати", systemImage: "plus.circle.fill")
                                .labelStyle(.iconOnly)
                        }
                        .buttonStyle(.borderless)
                        .disabled(name.isEmpty)
                    }
                }
                Section("Заплановано") {
                    if purchases.isEmpty {
                        Text("Список покупок порожній.").foregroundStyle(.secondary)
                    }
                    ForEach(purchases) { purchase in
                        HStack {
                            Text(purchase.name)
                            Spacer()
                            Button("Куплено") { buying = purchase }
                                .buttonStyle(.bordered)
                        }
                        .swipeActions {
                            Button("Видалити", role: .destructive) {
                                context.delete(purchase)
                                saveChanges()
                            }
                        }
                    }
                }
            }
            .navigationTitle("План покупок")
            .sheet(item: $buying) { purchase in
                ExpenseForm(purchase: purchase) { _ in }
            }
            .alert("Не вдалося зберегти зміни", isPresented: $saveFailed) {
                Button("Гаразд") {}
            }
        }
    }

    private func add() {
        guard !name.isEmpty else { return }
        context.insert(PlannedPurchase(name: name))
        if saveChanges() { draft = "" }
    }

    @discardableResult
    private func saveChanges() -> Bool {
        do {
            try context.save()
            return true
        } catch {
            context.rollback()
            saveFailed = true
            return false
        }
    }
}
