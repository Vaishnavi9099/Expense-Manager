import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

// ============================================================
// NOTIFICATION SERVICE
// ============================================================

class NotificationService {
  static final FlutterLocalNotificationsPlugin notifications =
      FlutterLocalNotificationsPlugin();

  static Future<void> initialize() async {
    tz.initializeTimeZones();

    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings settings = InitializationSettings(
      android: androidSettings,
    );

    await notifications.initialize(settings);

    await notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  static Future<void> showNotification({
    required int id,
    required String title,
    required String body,
  }) async {
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      'expense_manager_channel',
      'Expense Manager Notifications',
      channelDescription: 'Expense and budget notifications',
      importance: Importance.high,
      priority: Priority.high,
    );

    const NotificationDetails details = NotificationDetails(
      android: androidDetails,
    );

    await notifications.show(
      id,
      title,
      body,
      details,
    );
  }

  static Future<void> scheduleReminder({
    required int hour,
    required int minute,
  }) async {
    final now = tz.TZDateTime.now(tz.local);

    var scheduledDate = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );

    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }

    await notifications.zonedSchedule(
      100,
      'Expense Reminder',
      'Don\'t forget to add your expenses today!',
      scheduledDate,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'expense_reminder_channel',
          'Expense Reminders',
          channelDescription: 'Reminder to add expenses',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  static Future<void> cancelReminder() async {
    await notifications.cancel(100);
  }
}

// ============================================================
// MAIN
// ============================================================

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await NotificationService.initialize();

  runApp(const ExpenseApp());
}

// ============================================================
// EXPENSE APP
// ============================================================

class ExpenseApp extends StatefulWidget {
  const ExpenseApp({super.key});

  @override
  State<ExpenseApp> createState() => _ExpenseAppState();
}

class _ExpenseAppState extends State<ExpenseApp> {
  bool darkMode = false;

  void toggleDarkMode(bool value) {
    setState(() {
      darkMode = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Expense Manager',

      themeMode:
          darkMode ? ThemeMode.dark : ThemeMode.light,

      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
        brightness: Brightness.light,
      ),

      darkTheme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
        brightness: Brightness.dark,
      ),

      home: BottomNavScreen(
        darkMode: darkMode,
        onDarkModeChanged: toggleDarkMode,
      ),
    );
  }
}
// ============================================================
// BOTTOM NAVIGATION
// ============================================================
class BottomNavScreen extends StatefulWidget {
  final bool darkMode;
  final Function(bool) onDarkModeChanged;

  const BottomNavScreen({
    super.key,
    required this.darkMode,
    required this.onDarkModeChanged,
  });

  @override
  State<BottomNavScreen> createState() => _BottomNavScreenState();
}
class _BottomNavScreenState extends State<BottomNavScreen> {
  int _selectedIndex = 0;

  List<Map<String, dynamic>> expenses = [];

  double budget = 0.0;


  // ==========================================================
  // NOTIFICATION SETTINGS
  // ==========================================================

  bool notificationsEnabled = true;

  // Budget alert settings
  bool budgetAlerts = true;

  // User can select 80, 90 or 100
  int budgetThreshold = 80;

  // Expense added
  bool expenseAddedAlert = true;

  // Weekly summary
  bool weeklySummary = false;

  // Monthly summary
  bool monthlySummary = false;

  // Reminder
  bool expenseReminder = false;

  TimeOfDay reminderTime = const TimeOfDay(
    hour: 20,
    minute: 0,
  );

  // High expense alert
  bool highExpenseAlert = false;

  double highExpenseAmount = 1000;

  // Category budget alerts
  bool categoryBudgetAlerts = false;

  Map<String, double> categoryBudgets = {
    'Food': 0,
    'Shopping': 0,
    'Traveling': 0,
    'Rent': 0,
    'Entertainment': 0,
    'Bills': 0,
    'Others': 0,
  };

  // ==========================================================
  // NAVIGATION
  // ==========================================================

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  // ==========================================================
  // ADD EXPENSE
  // ==========================================================

  void addExpense(
    String category,
    double amount,
    DateTime date,
  ) {
    setState(() {
      expenses.add({
        'category': category,
        'amount': amount,
        'date': date,
      });
    });

    // ========================================================
    // EXPENSE ADDED NOTIFICATION
    // ========================================================

    if (notificationsEnabled && expenseAddedAlert) {
      NotificationService.showNotification(
        id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        title: 'Expense Added',
        body:
            '₹${amount.toStringAsFixed(2)} added to your $category expenses.',
      );
    }

    // ========================================================
    // HIGH EXPENSE ALERT
    // ========================================================

    if (notificationsEnabled &&
        highExpenseAlert &&
        amount >= highExpenseAmount) {
      NotificationService.showNotification(
        id: 200,
        title: 'High Expense Alert',
        body:
            'You added a high expense of ₹${amount.toStringAsFixed(2)}.',
      );
    }

    // ========================================================
    // BUDGET ALERT
    // ========================================================

    checkBudgetAlert();

    // ========================================================
    // CATEGORY BUDGET ALERT
    // ========================================================

    checkCategoryBudgetAlert(category);
  }

  // ==========================================================
  // BUDGET ALERT CHECK
  // ==========================================================

  void checkBudgetAlert() {
    if (!notificationsEnabled) return;

    if (!budgetAlerts) return;

    if (budget <= 0) return;

    double total = expenses.fold(
      0.0,
      (sum, item) => sum + (item['amount'] as double),
    );

    double percentage = (total / budget) * 100;

    if (percentage >= budgetThreshold && percentage < 100) {
      NotificationService.showNotification(
        id: 300,
        title: 'Budget Alert',
        body:
            'You have used ${percentage.toStringAsFixed(0)}% of your budget.',
      );
    }

    if (percentage >= 100) {
      NotificationService.showNotification(
        id: 301,
        title: 'Budget Exceeded!',
        body:
            'Your expenses have exceeded your total budget of ₹${budget.toStringAsFixed(2)}.',
      );
    }
  }

  // ==========================================================
  // CATEGORY BUDGET ALERT
  // ==========================================================

  void checkCategoryBudgetAlert(String category) {
    if (!notificationsEnabled) return;

    if (!categoryBudgetAlerts) return;

    double categoryLimit = categoryBudgets[category] ?? 0;

    if (categoryLimit <= 0) return;

    double categoryTotal = 0;

    for (var expense in expenses) {
      if (expense['category'] == category) {
        categoryTotal += expense['amount'] as double;
      }
    }

    if (categoryTotal >= categoryLimit) {
      NotificationService.showNotification(
        id: 400 + category.hashCode.abs() % 100,
        title: '$category Budget Alert',
        body:
            'Your $category expenses have reached ₹${categoryTotal.toStringAsFixed(2)}.',
      );
    }
  }

  // ==========================================================
  // DELETE EXPENSE
  // ==========================================================

  void deleteExpense(int index) {
    setState(() {
      expenses.removeAt(index);
    });
  }

  // ==========================================================
  // SET BUDGET
  // ==========================================================

  void setBudget(double newBudget) {
    setState(() {
      budget = newBudget;
    });
  }

  // ==========================================================
  // UPDATE NOTIFICATION SETTINGS
  // ==========================================================

  void updateNotificationSettings({
    bool? master,
    bool? budgetAlert,
    int? threshold,
    bool? expenseAlert,
    bool? weekly,
    bool? monthly,
    bool? reminder,
    TimeOfDay? reminderTimeValue,
    bool? highExpense,
    double? highExpenseLimit,
    bool? categoryAlerts,
  }) {
    setState(() {
      if (master != null) {
        notificationsEnabled = master;
      }

      if (budgetAlert != null) {
        budgetAlerts = budgetAlert;
      }

      if (threshold != null) {
        budgetThreshold = threshold;
      }

      if (expenseAlert != null) {
        expenseAddedAlert = expenseAlert;
      }

      if (weekly != null) {
        weeklySummary = weekly;
      }

      if (monthly != null) {
        monthlySummary = monthly;
      }

      if (reminder != null) {
        expenseReminder = reminder;
      }

      if (reminderTimeValue != null) {
        reminderTime = reminderTimeValue;
      }

      if (highExpense != null) {
        highExpenseAlert = highExpense;
      }

      if (highExpenseLimit != null) {
        highExpenseAmount = highExpenseLimit;
      }

      if (categoryAlerts != null) {
        categoryBudgetAlerts = categoryAlerts;
      }
    });

    // ========================================================
    // MASTER SWITCH OFF
    // Cancel scheduled reminder
    // ========================================================

    if (!notificationsEnabled) {
      NotificationService.cancelReminder();
    }

    // ========================================================
    // REMINDER
    // Only schedule if MASTER + REMINDER are ON
    // ========================================================

    if (notificationsEnabled && expenseReminder) {
      NotificationService.scheduleReminder(
        hour: reminderTime.hour,
        minute: reminderTime.minute,
      );
    } else {
      NotificationService.cancelReminder();
    }
  }

  // ==========================================================
  // BUILD
  // ==========================================================

  @override
  Widget build(BuildContext context) {
    final List<Widget> pages = [
      HomePage(
        expenses: expenses,
        onDelete: deleteExpense,
      ),

      AddExpensePage(
        onAddExpense: addExpense,
      ),

      BudgetPage(
        budget: budget,
        expenses: expenses,
        onSetBudget: setBudget,
      ),

      ProfilePage(
  notificationsEnabled: notificationsEnabled,
  budgetAlerts: budgetAlerts,
  budgetThreshold: budgetThreshold,
  expenseAddedAlert: expenseAddedAlert,
  weeklySummary: weeklySummary,
  monthlySummary: monthlySummary,
  expenseReminder: expenseReminder,
  reminderTime: reminderTime,
  highExpenseAlert: highExpenseAlert,
  highExpenseAmount: highExpenseAmount,
  categoryBudgetAlerts: categoryBudgetAlerts,
  onNotificationSettingsChanged: updateNotificationSettings,

  darkMode: widget.darkMode,
  onDarkModeChanged: widget.onDarkModeChanged,
),
    ];

    return Scaffold(
      body: pages[_selectedIndex],

      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        type: BottomNavigationBarType.fixed,

        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: 'Home',
          ),

          BottomNavigationBarItem(
            icon: Icon(Icons.add),
            label: 'Add',
          ),

          BottomNavigationBarItem(
            icon: Icon(Icons.account_balance_wallet),
            label: 'Budget',
          ),

          BottomNavigationBarItem(
            icon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

// ============================================================
// HOME PAGE
// ============================================================

class HomePage extends StatelessWidget {
  final List<Map<String, dynamic>> expenses;
  final Function(int) onDelete;

  const HomePage({
    super.key,
    required this.expenses,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    double total = expenses.fold(
      0.0,
      (sum, item) => sum + (item['amount'] as double),
    );

    return Scaffold(
      backgroundColor: Colors.blue,

      appBar: AppBar(
        title: const Text('Home'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        elevation: 0,
      ),

      body: Column(
        children: [
          // TOTAL EXPENSE CARD

          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(20),

            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),

            child: Column(
              children: [
                const Text(
                  'Total Expenses',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.black54,
                  ),
                ),

                const SizedBox(height: 10),

                Text(
                  '₹${total.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
              ],
            ),
          ),

          // EXPENSE LIST

          Expanded(
            child: expenses.isEmpty
                ? const Center(
                    child: Text(
                      'No expenses added yet.',
                      style: TextStyle(
                        color: Colors.white,
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: expenses.length,
                    itemBuilder: (context, index) {
                      final exp = expenses[index];

                      return Card(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),

                        margin: const EdgeInsets.symmetric(
                          vertical: 8,
                        ),

                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor:
                                _getCategoryColor(exp['category']),

                            child: Icon(
                              _getCategoryIcon(exp['category']),
                              color: Colors.white,
                            ),
                          ),

                          title: Text(
                            exp['category'],
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                            ),
                          ),

                          subtitle: Text(
                            '${exp['date'].toLocal()}'.split(' ')[0],
                          ),

                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '₹${(exp['amount'] as double).toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),

                              IconButton(
                                icon: const Icon(
                                  Icons.delete,
                                  color: Colors.red,
                                ),

                                onPressed: () {
                                  onDelete(index);

                                  ScaffoldMessenger.of(context)
                                      .showSnackBar(
                                    const SnackBar(
                                      content:
                                          Text('Expense Deleted'),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  IconData _getCategoryIcon(String category) {
    switch (category.toLowerCase()) {
      case 'food':
        return Icons.restaurant;

      case 'traveling':
        return Icons.flight;

      case 'shopping':
        return Icons.shopping_bag;

      case 'rent':
        return Icons.home;

      case 'entertainment':
        return Icons.movie;

      case 'bills':
        return Icons.receipt_long;

      default:
        return Icons.category;
    }
  }

  Color _getCategoryColor(String category) {
    switch (category.toLowerCase()) {
      case 'food':
        return Colors.red;

      case 'traveling':
        return Colors.blue;

      case 'shopping':
        return Colors.green;

      case 'rent':
        return Colors.orange;

      case 'entertainment':
        return Colors.purple;

      case 'bills':
        return Colors.teal;

      default:
        return Colors.grey;
    }
  }
}

// ============================================================
// ADD EXPENSE PAGE
// ============================================================

class AddExpensePage extends StatefulWidget {
  final Function(String, double, DateTime) onAddExpense;

  const AddExpensePage({
    super.key,
    required this.onAddExpense,
  });

  @override
  State<AddExpensePage> createState() => _AddExpensePageState();
}

class _AddExpensePageState extends State<AddExpensePage> {
  final _amountController = TextEditingController();

  String _selectedCategory = 'Food';

  DateTime _selectedDate = DateTime.now();

  final List<String> _categories = [
    'Food',
    'Shopping',
    'Traveling',
    'Rent',
    'Entertainment',
    'Bills',
    'Others',
  ];

  Future<void> _presentDatePicker() async {
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );

    if (pickedDate != null) {
      setState(() {
        _selectedDate = pickedDate;
      });
    }
  }

  void _saveData() {
    if (_amountController.text.isEmpty) {
      return;
    }

    final enteredAmount =
        double.tryParse(_amountController.text);

    if (enteredAmount == null || enteredAmount <= 0) {
      return;
    }

    widget.onAddExpense(
      _selectedCategory,
      enteredAmount,
      _selectedDate,
    );

    _amountController.clear();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Expense Added Successfully!',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.blue.shade600,

      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 16),

            const Text(
              'Add Expense',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),

            const SizedBox(height: 16),

            Expanded(
              child: Container(
                padding: const EdgeInsets.all(20),

                decoration: const BoxDecoration(
                  color: Colors.white,

                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(25),
                    topRight: Radius.circular(25),
                  ),
                ),

                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,

                    children: [
                      const Text(
                        'Amount',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),

                      const SizedBox(height: 8),

                      TextField(
                        controller: _amountController,
                        keyboardType:
                            TextInputType.number,

                        decoration: InputDecoration(
                          hintText: 'Enter amount',

                          border:
                              OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(12),
                          ),
                        ),
                      ),

                      const SizedBox(height: 16),

                      const Text(
                        'Category',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),

                      const SizedBox(height: 8),

                      DropdownButtonFormField<String>(
                        value: _selectedCategory,

                        items: _categories.map(
                          (category) {
                            return DropdownMenuItem(
                              value: category,

                              child: Text(category),
                            );
                          },
                        ).toList(),

                        onChanged: (value) {
                          setState(() {
                            _selectedCategory =
                                value!;
                          });
                        },

                        decoration:
                            InputDecoration(
                          border:
                              OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(12),
                          ),
                        ),
                      ),

                      const SizedBox(height: 16),

                      const Text(
                        'Date',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),

                      const SizedBox(height: 8),

                      GestureDetector(
                        onTap: _presentDatePicker,

                        child: Container(
                          padding:
                              const EdgeInsets.all(14),

                          decoration:
                              BoxDecoration(
                            border: Border.all(
                              color: Colors.grey,
                            ),

                            borderRadius:
                                BorderRadius.circular(12),
                          ),

                          child: Row(
                            children: [
                              const Icon(
                                Icons.calendar_today,
                                color: Colors.blue,
                              ),

                              const SizedBox(width: 8),

                              Text(
                                DateFormat(
                                  'dd MMM yyyy',
                                ).format(
                                  _selectedDate,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 24),

                      Center(
                        child: ElevatedButton(
                          onPressed: _saveData,

                          style:
                              ElevatedButton.styleFrom(
                            backgroundColor:
                                Colors.blue.shade600,

                            padding:
                                const EdgeInsets.symmetric(
                              horizontal: 100,
                              vertical: 14,
                            ),
                          ),

                          child: const Text(
                            'Save',
                            style: TextStyle(
                              fontSize: 18,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// BUDGET PAGE
// ============================================================

class BudgetPage extends StatefulWidget {
  final double budget;

  final List<Map<String, dynamic>> expenses;

  final Function(double) onSetBudget;

  const BudgetPage({
    super.key,
    required this.budget,
    required this.expenses,
    required this.onSetBudget,
  });

  @override
  State<BudgetPage> createState() => _BudgetPageState();
}

class _BudgetPageState extends State<BudgetPage> {
  final _budgetController =
      TextEditingController();

  @override
  Widget build(BuildContext context) {
    double totalExpenses =
        widget.expenses.fold(
      0.0,
      (sum, item) =>
          sum + (item['amount'] as double),
    );

    double remaining =
        widget.budget - totalExpenses;

    if (remaining < 0) {
      remaining = 0;
    }

    Map<String, double> categoryData = {};

    for (var exp in widget.expenses) {
      String category = exp['category'];

      categoryData[category] =
          (categoryData[category] ?? 0) +
              (exp['amount'] as double);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Budget'),
      ),

      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),

        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,

          children: [
            Text(
              'Your Current Budget: ₹${widget.budget.toStringAsFixed(2)}',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 10),

            Text(
              'Total Expenses: ₹${totalExpenses.toStringAsFixed(2)}',
              style: const TextStyle(
                fontSize: 18,
                color: Colors.red,
              ),
            ),

            const SizedBox(height: 10),

            Text(
              'Remaining: ₹${remaining.toStringAsFixed(2)}',
              style: const TextStyle(
                fontSize: 18,
                color: Colors.green,
              ),
            ),

            const SizedBox(height: 30),

            const Text(
              'Category-wise Expenses',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 20),

            SizedBox(
              height: 250,

              child: categoryData.isEmpty
                  ? const Center(
                      child: Text(
                        'No expense data available',
                      ),
                    )
                  : BarChart(
                      BarChartData(
                        borderData:
                            FlBorderData(
                          show: false,
                        ),

                        gridData:
                            const FlGridData(
                          show: false,
                        ),

                        barGroups:
                            List.generate(
                          categoryData.length,
                          (index) {
                            final key =
                                categoryData.keys
                                    .elementAt(
                              index,
                            );

                            final value =
                                categoryData[key]!;

                            return BarChartGroupData(
                              x: index,

                              barRods: [
                                BarChartRodData(
                                  toY: value,
                                  width: 20,
                                  color:
                                      Colors.blue,
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ),
            ),

            const SizedBox(height: 30),

            TextField(
              controller:
                  _budgetController,

              decoration:
                  const InputDecoration(
                labelText: 'Enter Budget',

                border:
                    OutlineInputBorder(),
              ),

              keyboardType:
                  TextInputType.number,
            ),

            const SizedBox(height: 20),

            SizedBox(
              width: double.infinity,

              child: ElevatedButton(
                onPressed: () {
                  if (_budgetController
                      .text
                      .isNotEmpty) {
                    double newBudget =
                        double.tryParse(
                              _budgetController
                                  .text,
                            ) ??
                            0;

                    if (newBudget > 0) {
                      widget.onSetBudget(
                        newBudget,
                      );

                      _budgetController
                          .clear();

                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Budget Updated!',
                          ),
                        ),
                      );
                    }
                  }
                },

                child:
                    const Text('Set Budget'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// PROFILE PAGE
// ============================================================

class ProfilePage extends StatefulWidget {
  final bool darkMode;
  final Function(bool) onDarkModeChanged;
  final bool notificationsEnabled;
  final bool budgetAlerts;
  final int budgetThreshold;
  final bool expenseAddedAlert;
  final bool weeklySummary;
  final bool monthlySummary;
  final bool expenseReminder;
  final TimeOfDay reminderTime;
  final bool highExpenseAlert;
  final double highExpenseAmount;
  final bool categoryBudgetAlerts;
 

  final Function({
    bool? master,
    bool? budgetAlert,
    int? threshold,
    bool? expenseAlert,
    bool? weekly,
    bool? monthly,
    bool? reminder,
    TimeOfDay? reminderTimeValue,
    bool? highExpense,
    double? highExpenseLimit,
    bool? categoryAlerts,
  }) onNotificationSettingsChanged;

  const ProfilePage({
    super.key,
    required this.darkMode,
    required this.onDarkModeChanged,
    required this.notificationsEnabled,
    required this.budgetAlerts,
    required this.budgetThreshold,
    required this.expenseAddedAlert,
    required this.weeklySummary,
    required this.monthlySummary,
    required this.expenseReminder,
    required this.reminderTime,
    required this.highExpenseAlert,
    required this.highExpenseAmount,
    required this.categoryBudgetAlerts,
    required this.onNotificationSettingsChanged,
  });

  @override
  State<ProfilePage> createState() =>
      _ProfilePageState();
}

class _ProfilePageState
    extends State<ProfilePage> {
  String name = 'Demo User';

  String email = 'demo@example.com';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),

        backgroundColor:
            Colors.blue,

        foregroundColor:
            Colors.white,
      ),

      body: SingleChildScrollView(
        padding:
            const EdgeInsets.all(20),

        child: Column(
          children: [
            const CircleAvatar(
              radius: 60,

              backgroundColor:
                  Colors.blue,

              child: Icon(
                Icons.person,
                size: 70,
                color: Colors.white,
              ),
            ),

            const SizedBox(height: 20),

            Text(
              name,

              style:
                  const TextStyle(
                fontSize: 24,
                fontWeight:
                    FontWeight.bold,
              ),
            ),

            const SizedBox(height: 5),

            Text(
              email,

              style:
                  const TextStyle(
                fontSize: 16,
                color: Colors.grey,
              ),
            ),

            const SizedBox(height: 30),

            SizedBox(
              width:
                  double.infinity,

              child:
                  ElevatedButton.icon(
                onPressed: () async {
                  final result =
                      await Navigator.push(
                    context,

                    MaterialPageRoute(
                      builder:
                          (context) =>
                              EditProfilePage(
                        currentName:
                            name,

                        currentEmail:
                            email,
                      ),
                    ),
                  );

                  if (result != null) {
                    setState(() {
                      name =
                          result['name'];

                      email =
                          result['email'];
                    });
                  }
                },

                icon:
                    const Icon(
                  Icons.edit,
                ),

                label:
                    const Text(
                  'Edit Profile',
                ),
              ),
            ),

            const SizedBox(height: 20),

            // NOTIFICATIONS

            Card(
              child: ListTile(
                leading:
                    const Icon(
                  Icons.notifications,
                  color:
                      Colors.blue,
                ),

                title:
                    const Text(
                  'Notifications',
                ),

                subtitle:
                    Text(
                  widget.notificationsEnabled
                      ? 'Notifications are ON'
                      : 'Notifications are OFF',
                ),

                trailing:
                    const Icon(
                  Icons
                      .arrow_forward_ios,
                  size: 16,
                ),

                onTap: () {
                  Navigator.push(
                    context,

                    MaterialPageRoute(
                      builder:
                          (context) =>
                              NotificationsPage(
                        notificationsEnabled:
                            widget
                                .notificationsEnabled,

                        budgetAlerts:
                            widget
                                .budgetAlerts,

                        budgetThreshold:
                            widget
                                .budgetThreshold,

                        expenseAddedAlert:
                            widget
                                .expenseAddedAlert,

                        weeklySummary:
                            widget
                                .weeklySummary,

                        monthlySummary:
                            widget
                                .monthlySummary,

                        expenseReminder:
                            widget
                                .expenseReminder,

                        reminderTime:
                            widget
                                .reminderTime,

                        highExpenseAlert:
                            widget
                                .highExpenseAlert,

                        highExpenseAmount:
                            widget
                                .highExpenseAmount,

                        categoryBudgetAlerts:
                            widget
                                .categoryBudgetAlerts,

                        onSettingsChanged:
                            widget
                                .onNotificationSettingsChanged,
                      ),
                    ),
                  );
                },
              ),
            ),

            // SETTINGS

            Card(
              child: ListTile(
                leading:
                    const Icon(
                  Icons.settings,
                  color:
                      Colors.blue,
                ),

                title:
                    const Text(
                  'Settings',
                ),

                trailing:
                    const Icon(
                  Icons
                      .arrow_forward_ios,
                  size: 16,
                ),

                onTap: () {
                  Navigator.push(
                    context,

                    MaterialPageRoute(
                      builder:
                          (context) =>
                              const SettingsPage(),
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: 20),

            SizedBox(
              width:
                  double.infinity,

              child:
                  OutlinedButton.icon(
                onPressed: () {},

                icon:
                    const Icon(
                  Icons.logout,
                  color: Colors.red,
                ),

                label:
                    const Text(
                  'Logout',

                  style:
                      TextStyle(
                    color: Colors.red,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// NOTIFICATIONS PAGE
// ============================================================

class NotificationsPage
    extends StatefulWidget {
  final bool notificationsEnabled;
  final bool budgetAlerts;
  final int budgetThreshold;
  final bool expenseAddedAlert;
  final bool weeklySummary;
  final bool monthlySummary;
  final bool expenseReminder;
  final TimeOfDay reminderTime;
  final bool highExpenseAlert;
  final double highExpenseAmount;
  final bool categoryBudgetAlerts;

  final Function({
    bool? master,
    bool? budgetAlert,
    int? threshold,
    bool? expenseAlert,
    bool? weekly,
    bool? monthly,
    bool? reminder,
    TimeOfDay? reminderTimeValue,
    bool? highExpense,
    double? highExpenseLimit,
    bool? categoryAlerts,
  }) onSettingsChanged;

  const NotificationsPage({
    super.key,
    required this.notificationsEnabled,
    required this.budgetAlerts,
    required this.budgetThreshold,
    required this.expenseAddedAlert,
    required this.weeklySummary,
    required this.monthlySummary,
    required this.expenseReminder,
    required this.reminderTime,
    required this.highExpenseAlert,
    required this.highExpenseAmount,
    required this.categoryBudgetAlerts,
    required this.onSettingsChanged,
  });

  @override
  State<NotificationsPage> createState() =>
      _NotificationsPageState();
}

class _NotificationsPageState
    extends State<NotificationsPage> {
  late bool notificationsEnabled;

  late bool budgetAlerts;

  late int budgetThreshold;

  late bool expenseAddedAlert;

  late bool weeklySummary;

  late bool monthlySummary;

  late bool expenseReminder;

  late TimeOfDay reminderTime;

  late bool highExpenseAlert;

  late double highExpenseAmount;

  late bool categoryBudgetAlerts;

  @override
  void initState() {
    super.initState();

    notificationsEnabled =
        widget.notificationsEnabled;

    budgetAlerts =
        widget.budgetAlerts;

    budgetThreshold =
        widget.budgetThreshold;

    expenseAddedAlert =
        widget.expenseAddedAlert;

    weeklySummary =
        widget.weeklySummary;

    monthlySummary =
        widget.monthlySummary;

    expenseReminder =
        widget.expenseReminder;

    reminderTime =
        widget.reminderTime;

    highExpenseAlert =
        widget.highExpenseAlert;

    highExpenseAmount =
        widget.highExpenseAmount;

    categoryBudgetAlerts =
        widget.categoryBudgetAlerts;
  }

  void updateSettings() {
    widget.onSettingsChanged(
      master:
          notificationsEnabled,

      budgetAlert:
          budgetAlerts,

      threshold:
          budgetThreshold,

      expenseAlert:
          expenseAddedAlert,

      weekly:
          weeklySummary,

      monthly:
          monthlySummary,

      reminder:
          expenseReminder,

      reminderTimeValue:
          reminderTime,

      highExpense:
          highExpenseAlert,

      highExpenseLimit:
          highExpenseAmount,

      categoryAlerts:
          categoryBudgetAlerts,
    );
  }

  Future<void> selectReminderTime() async {
    final picked =
        await showTimePicker(
      context: context,
      initialTime:
          reminderTime,
    );

    if (picked != null) {
      setState(() {
        reminderTime =
            picked;
      });

      updateSettings();
    }
  }

  Future<void>
      selectHighExpenseAmount() async {
    final controller =
        TextEditingController(
      text:
          highExpenseAmount
              .toStringAsFixed(0),
    );

    await showDialog(
      context: context,

      builder:
          (context) =>
              AlertDialog(
        title: const Text(
          'High Expense Amount',
        ),

        content:
            TextField(
          controller:
              controller,

          keyboardType:
              TextInputType.number,

          decoration:
              const InputDecoration(
            prefixText: '₹ ',
            hintText:
                'Enter amount',
          ),
        ),

        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(
                  context);
            },

            child:
                const Text(
              'Cancel',
            ),
          ),

          ElevatedButton(
            onPressed: () {
              final value =
                  double.tryParse(
                controller.text,
              );

              if (value != null &&
                  value > 0) {
                setState(() {
                  highExpenseAmount =
                      value;
                });

                updateSettings();
              }

              Navigator.pop(
                  context);
            },

            child:
                const Text(
              'Save',
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(
      BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title:
            const Text(
          'Notifications',
        ),

        backgroundColor:
            Colors.blue,

        foregroundColor:
            Colors.white,
      ),

      body: ListView(
        padding:
            const EdgeInsets.all(16),

        children: [
          // ==================================================
          // MASTER SWITCH
          // ==================================================

          const Text(
            'General',
            style:
                TextStyle(
              fontSize: 18,
              fontWeight:
                  FontWeight.bold,
            ),
          ),

          const SizedBox(
              height: 10),

          Card(
            child:
                SwitchListTile(
              secondary:
                  const Icon(
                Icons
                    .notifications_active,
                color:
                    Colors.blue,
              ),

              title:
                  const Text(
                '🔔 Enable Notifications',
              ),

              subtitle:
                  Text(
                notificationsEnabled
                    ? 'All enabled alerts are active'
                    : 'All notifications are disabled',
              ),

              value:
                  notificationsEnabled,

              onChanged:
                  (value) {
                setState(() {
                  notificationsEnabled =
                      value;
                });

                updateSettings();
              },
            ),
          ),

          const SizedBox(
              height: 20),

          // ==================================================
          // BUDGET ALERTS
          // ==================================================

          const Text(
            '💰 Budget Alerts',
            style:
                TextStyle(
              fontSize: 18,
              fontWeight:
                  FontWeight.bold,
            ),
          ),

          Card(
            child:
                SwitchListTile(
              title:
                  const Text(
                'Enable Budget Alerts',
              ),

              subtitle:
                  const Text(
                'Get alerts when your budget reaches the selected threshold',
              ),

              value:
                  budgetAlerts,

              onChanged:
                  notificationsEnabled
                      ? (value) {
                          setState(() {
                            budgetAlerts =
                                value;
                          });

                          updateSettings();
                        }
                      : null,
            ),
          ),

          if (budgetAlerts &&
              notificationsEnabled)
            Card(
              child:
                  ListTile(
                leading:
                    const Icon(
                  Icons
                      .percent,
                  color:
                      Colors.blue,
                ),

                title:
                    const Text(
                  'Alert Threshold',
                ),

                subtitle:
                    Text(
                  'Alert me at $budgetThreshold% of budget',
                ),

                trailing:
                    DropdownButton<
                        int>(
                  value:
                      budgetThreshold,

                  items: const [
                    DropdownMenuItem(
                      value: 80,
                      child:
                          Text(
                              '80%'),
                    ),
                    DropdownMenuItem(
                      value: 90,
                      child:
                          Text(
                              '90%'),
                    ),
                    DropdownMenuItem(
                      value: 100,
                      child:
                          Text(
                              '100%'),
                    ),
                  ],

                  onChanged:
                      (value) {
                    if (value !=
                        null) {
                      setState(() {
                        budgetThreshold =
                            value;
                      });

                      updateSettings();
                    }
                  },
                ),
              ),
            ),

          const SizedBox(
              height: 20),

          // ==================================================
          // EXPENSE ADDED
          // ==================================================

          Card(
            child:
                SwitchListTile(
              secondary:
                  const Icon(
                Icons.add_chart,
                color:
                    Colors.blue,
              ),

              title:
                  const Text(
                '➕ Expense Added Alert',
              ),

              subtitle:
                  const Text(
                'Notify me whenever a new expense is added',
              ),

              value:
                  expenseAddedAlert,

              onChanged:
                  notificationsEnabled
                      ? (value) {
                          setState(() {
                            expenseAddedAlert =
                                value;
                          });

                          updateSettings();
                        }
                      : null,
            ),
          ),

          // ==================================================
          // WEEKLY SUMMARY
          // ==================================================

          Card(
            child:
                SwitchListTile(
              secondary:
                  const Icon(
                Icons
                    .bar_chart,
                color:
                    Colors.blue,
              ),

              title:
                  const Text(
                '📊 Weekly Expense Summary',
              ),

              subtitle:
                  const Text(
                'Receive a weekly expense summary',
              ),

              value:
                  weeklySummary,

              onChanged:
                  notificationsEnabled
                      ? (value) {
                          setState(() {
                            weeklySummary =
                                value;
                          });

                          updateSettings();
                        }
                      : null,
            ),
          ),

          // ==================================================
          // MONTHLY SUMMARY
          // ==================================================

          Card(
            child:
                SwitchListTile(
              secondary:
                  const Icon(
                Icons
                    .calendar_month,
                color:
                    Colors.blue,
              ),

              title:
                  const Text(
                '📅 Monthly Expense Summary',
              ),

              subtitle:
                  const Text(
                'Receive a monthly expense summary',
              ),

              value:
                  monthlySummary,

              onChanged:
                  notificationsEnabled
                      ? (value) {
                          setState(() {
                            monthlySummary =
                                value;
                          });

                          updateSettings();
                        }
                      : null,
            ),
          ),

          const SizedBox(
              height: 20),

          // ==================================================
          // EXPENSE REMINDER
          // ==================================================

          Card(
            child:
                SwitchListTile(
              secondary:
                  const Icon(
                Icons
                    .access_alarm,
                color:
                    Colors.blue,
              ),

              title:
                  const Text(
                '⏰ Reminder to Add Expenses',
              ),

              subtitle:
                  Text(
                expenseReminder
                    ? 'Reminder at ${reminderTime.format(context)}'
                    : 'Turn on to receive a daily reminder',
              ),

              value:
                  expenseReminder,

              onChanged:
                  notificationsEnabled
                      ? (value) {
                          setState(() {
                            expenseReminder =
                                value;
                          });

                          updateSettings();
                        }
                      : null,
            ),
          ),

          if (expenseReminder &&
              notificationsEnabled)
            Card(
              child:
                  ListTile(
                leading:
                    const Icon(
                  Icons
                      .schedule,
                  color:
                      Colors.blue,
                ),

                title:
                    const Text(
                  'Choose Reminder Time',
                ),

                trailing:
                    TextButton(
                  onPressed:
                      selectReminderTime,

                  child:
                      Text(
                    reminderTime
                        .format(
                            context),
                  ),
                ),
              ),
            ),

          const SizedBox(
              height: 20),

          // ==================================================
          // HIGH EXPENSE ALERT
          // ==================================================

          Card(
            child:
                SwitchListTile(
              secondary:
                  const Icon(
                Icons
                    .trending_up,
                color:
                    Colors.blue,
              ),

              title:
                  const Text(
                '📈 High Expense Alert',
              ),

              subtitle:
                  Text(
                highExpenseAlert
                    ? 'Alert when expense exceeds ₹${highExpenseAmount.toStringAsFixed(0)}'
                    : 'Alert for unusually high expenses',
              ),

              value:
                  highExpenseAlert,

              onChanged:
                  notificationsEnabled
                      ? (value) {
                          setState(() {
                            highExpenseAlert =
                                value;
                          });

                          updateSettings();
                        }
                      : null,
            ),
          ),

          if (highExpenseAlert &&
              notificationsEnabled)
            Card(
              child:
                  ListTile(
                leading:
                    const Icon(
                  Icons
                      .currency_rupee,
                  color:
                      Colors.blue,
                ),

                title:
                    const Text(
                  'Choose High Expense Limit',
                ),

                trailing:
                    TextButton(
                  onPressed:
                      selectHighExpenseAmount,

                  child:
                      Text(
                    '₹${highExpenseAmount.toStringAsFixed(0)}',
                  ),
                ),
              ),
            ),

          const SizedBox(
              height: 20),

          // ==================================================
          // CATEGORY BUDGET
          // ==================================================

          Card(
            child:
                SwitchListTile(
              secondary:
                  const Icon(
                Icons
                    .category,
                color:
                    Colors.blue,
              ),

              title:
                  const Text(
                '🏷️ Category Budget Alerts',
              ),

              subtitle:
                  const Text(
                'Set individual spending limits for categories',
              ),

              value:
                  categoryBudgetAlerts,

              onChanged:
                  notificationsEnabled
                      ? (value) {
                          setState(() {
                            categoryBudgetAlerts =
                                value;
                          });

                          updateSettings();
                        }
                      : null,
            ),
          ),

          if (categoryBudgetAlerts &&
              notificationsEnabled)
            const Card(
              child:
                  Padding(
                padding:
                    EdgeInsets.all(16),

                child:
                    Text(
                  'You can set separate limits for Food, Shopping, Travel, Rent, and other categories.',
                ),
              ),
            ),

          const SizedBox(
              height: 30),

          // ==================================================
          // IMPORTANT INFO
          // ==================================================

          Container(
            padding:
                const EdgeInsets.all(16),

            decoration:
                BoxDecoration(
              color:
                  Colors.blue.shade50,

              borderRadius:
                  BorderRadius.circular(
                12,
              ),
            ),

            child:
                const Row(
              crossAxisAlignment:
                  CrossAxisAlignment.start,

              children: [
                Icon(
                  Icons.info_outline,
                  color:
                      Colors.blue,
                ),

                SizedBox(
                    width: 10),

                Expanded(
                  child:
                      Text(
                    'When Enable Notifications is OFF, the app will not show any new notifications and scheduled expense reminders will be cancelled.',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// SETTINGS PAGE
// ============================================================
// ============================================================
// SETTINGS PAGE
// ============================================================

class SettingsPage
    extends StatefulWidget {
  const SettingsPage({
    super.key,
  });

  @override
  State<SettingsPage> createState() =>
      _SettingsPageState();
}

class _SettingsPageState
    extends State<SettingsPage> {
  String selectedCurrency =
      '₹';

  bool darkMode = false;

  @override
  Widget build(
      BuildContext context) {
    return Theme(
      data: darkMode
          ? ThemeData(
              brightness:
                  Brightness.dark,
              primarySwatch:
                  Colors.blue,
              useMaterial3: true,
            )
          : ThemeData(
              brightness:
                  Brightness.light,
              primarySwatch:
                  Colors.blue,
              useMaterial3: true,
            ),

      child: Scaffold(
        appBar: AppBar(
          title:
              const Text(
            'Settings',
          ),

          backgroundColor:
              Colors.blue,

          foregroundColor:
              Colors.white,
        ),

        body: ListView(
          padding:
              const EdgeInsets.all(16),

          children: [
            const Text(
              'Appearance',
              style:
                  TextStyle(
                fontSize: 18,
                fontWeight:
                    FontWeight.bold,
              ),
            ),

            const SizedBox(
                height: 10),

            Card(
              child:
                  SwitchListTile(
                secondary:
                    const Icon(
                  Icons.dark_mode,
                  color:
                      Colors.blue,
                ),

                title:
                    const Text(
                  'Dark Mode',
                ),

                value:
                    darkMode,

                onChanged:
                    (value) {
                  setState(() {
                    darkMode =
                        value;
                  });
                },
              ),
            ),

            const SizedBox(
                height: 20),

            const Text(
              'Currency',
              style:
                  TextStyle(
                fontSize: 18,
                fontWeight:
                    FontWeight.bold,
              ),
            ),

            const SizedBox(
                height: 10),

            Card(
              child:
                  ListTile(
                leading:
                    const Icon(
                  Icons
                      .currency_exchange,
                  color:
                      Colors.blue,
                ),

                title:
                    const Text(
                  'Currency',
                ),

                subtitle:
                    Text(
                  'Selected currency: $selectedCurrency',
                ),

                trailing:
                    DropdownButton<
                        String>(
                  value:
                      selectedCurrency,

                  underline:
                      const SizedBox(),

                  items: const [
                    DropdownMenuItem(
                      value: '₹',
                      child:
                          Text(
                        'INR (₹)',
                      ),
                    ),
                    DropdownMenuItem(
                      value: '\$',
                      child:
                          Text(
                        'USD (\$)',
                      ),
                    ),
                    DropdownMenuItem(
                      value: '€',
                      child:
                          Text(
                        'EUR (€)',
                      ),
                    ),
                    DropdownMenuItem(
                      value: '£',
                      child:
                          Text(
                        'GBP (£)',
                      ),
                    ),
                  ],

                  onChanged:
                      (value) {
                    if (value !=
                        null) {
                      setState(() {
                        selectedCurrency =
                            value;
                      });
                    }
                  },
                ),
              ),
            ),

            const SizedBox(
                height: 30),

            const Text(
              'About',
              style:
                  TextStyle(
                fontSize: 18,
                fontWeight:
                    FontWeight.bold,
              ),
            ),

            const SizedBox(
                height: 10),

            const Card(
              child:
                  ListTile(
                leading:
                    Icon(
                  Icons
                      .info_outline,
                  color:
                      Colors.blue,
                ),

                title:
                    Text(
                  'App Version',
                ),

                subtitle:
                    Text(
                  'Version 1.0.0',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// EDIT PROFILE PAGE
// ============================================================

class EditProfilePage
    extends StatefulWidget {
  final String currentName;

  final String currentEmail;

  const EditProfilePage({
    super.key,
    required this.currentName,
    required this.currentEmail,
  });

  @override
  State<EditProfilePage> createState() =>
      _EditProfilePageState();
}

class _EditProfilePageState
    extends State<EditProfilePage> {
  late TextEditingController
      _nameController;

  late TextEditingController
      _emailController;

  final TextEditingController
      _phoneController =
      TextEditingController();

  @override
  void initState() {
    super.initState();

    _nameController =
        TextEditingController(
      text: widget.currentName,
    );

    _emailController =
        TextEditingController(
      text: widget.currentEmail,
    );
  }

  @override
  void dispose() {
    _nameController.dispose();

    _emailController.dispose();

    _phoneController.dispose();

    super.dispose();
  }

  void _saveProfile() {
    if (_nameController.text
            .trim()
            .isEmpty ||
        _emailController.text
            .trim()
            .isEmpty) {
      ScaffoldMessenger.of(
              context)
          .showSnackBar(
        const SnackBar(
          content: Text(
            'Please fill all required fields',
          ),
        ),
      );

      return;
    }

    Navigator.pop(
      context,
      {
        'name':
            _nameController.text
                .trim(),

        'email':
            _emailController.text
                .trim(),

        'phone':
            _phoneController.text
                .trim(),
      },
    );
  }

  @override
  Widget build(
      BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title:
            const Text(
          'Edit Profile',
        ),

        backgroundColor:
            Colors.blue,

        foregroundColor:
            Colors.white,
      ),

      body:
          SingleChildScrollView(
        padding:
            const EdgeInsets.all(20),

        child: Column(
          children: [
            const CircleAvatar(
              radius: 60,

              backgroundColor:
                  Colors.blue,

              child: Icon(
                Icons.person,
                size: 70,
                color: Colors.white,
              ),
            ),

            const SizedBox(
                height: 30),

            TextField(
              controller:
                  _nameController,

              decoration:
                  const InputDecoration(
                labelText:
                    'Full Name',

                prefixIcon:
                    Icon(
                  Icons.person,
                ),

                border:
                    OutlineInputBorder(),
              ),
            ),

            const SizedBox(
                height: 20),

            TextField(
              controller:
                  _emailController,

              keyboardType:
                  TextInputType
                      .emailAddress,

              decoration:
                  const InputDecoration(
                labelText:
                    'Email',

                prefixIcon:
                    Icon(
                  Icons.email,
                ),

                border:
                    OutlineInputBorder(),
              ),
            ),

            const SizedBox(
                height: 20),

            TextField(
              controller:
                  _phoneController,

              keyboardType:
                  TextInputType.phone,

              decoration:
                  const InputDecoration(
                labelText:
                    'Phone Number',

                prefixIcon:
                    Icon(
                  Icons.phone,
                ),

                border:
                    OutlineInputBorder(),
              ),
            ),

            const SizedBox(
                height: 30),

            SizedBox(
              width:
                  double.infinity,

              height: 50,

              child:
                  ElevatedButton.icon(
                onPressed:
                    _saveProfile,

                icon:
                    const Icon(
                  Icons.save,
                ),

                label:
                    const Text(
                  'Save Changes',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}