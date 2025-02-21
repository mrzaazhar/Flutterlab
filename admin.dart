import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';

class AdminLandingPage extends StatefulWidget {
  const AdminLandingPage({Key? key}) : super(key: key);

  @override
  _AdminLandingPageState createState() => _AdminLandingPageState();
}

class _AdminLandingPageState extends State<AdminLandingPage>
    with SingleTickerProviderStateMixin {
  final DatabaseReference _bookingsRef =
      FirebaseDatabase.instance.ref().child('bookings');
  final DatabaseReference _deletedBookingsRef =
      FirebaseDatabase.instance.ref().child('deleted_bookings');
  final DatabaseReference _tempDeletedRef =
      FirebaseDatabase.instance.ref().child('temporary_deleted');

  List<Map<String, dynamic>> bookings = [];
  List<Map<String, dynamic>> deletedBookings = [];
  List<String> selectedBookings = [];
  bool isSelectAllBookingHistory = false;
  bool isSelectAllDeletedBookings = false;

  late TabController _tabController;

  List<Map<String, dynamic>> temporaryDeletedBookings = [];

  bool isSelectAllStudent = false;
  bool isSelectAllStaff = false;
  List<String> selectedStudentBookings = [];
  List<String> selectedStaffBookings = [];

  Future<void> _fetchBookings() async {
    try {
      final snapshot = await _bookingsRef.once();

      if (snapshot.snapshot.value != null) {
        final Map<dynamic, dynamic> data =
            snapshot.snapshot.value as Map<dynamic, dynamic>;
        print("Raw Firebase Data: $data"); // Debug print raw data

        setState(() {
          bookings = [];

          data.forEach((key, value) {
            if (value is Map) {
              final role = value['role']?.toString().toLowerCase() ?? 'student';
              final booking = {
                'id': key,
                'book_title':
                    value['book_title']?.toString() ?? 'No book title',
                'borrower_name':
                    value['borrower_name']?.toString() ?? 'No borrower',
                'borrow_date': value['borrow_date']?.toString() ?? 'Not set',
                'return_date': value['return_date']?.toString() ?? 'Not set',
                'status': value['status']?.toString() ?? 'Pending',
                'role': role,
              };
              print("Processing booking: $booking"); // Debug print each booking
              bookings.add(booking);
            }
          });
        });

        // Debug prints for filtered lists
        final studentBookings = bookings
            .where((booking) =>
                booking['role'].toString().toLowerCase() == 'student')
            .toList();

        final staffBookings = bookings
            .where((booking) =>
                booking['role'].toString().toLowerCase() == 'staff')
            .toList();

        print("Total bookings: ${bookings.length}");
        print("Student bookings: ${studentBookings.length}");
        print("Staff bookings: ${staffBookings.length}");
      } else {
        print("No data found in snapshot"); // Debug print for empty snapshot
        setState(() {
          bookings = [];
        });
      }
    } catch (e) {
      print('Error fetching bookings: $e');
      setState(() {
        bookings = [];
      });
    }
  }

  Future<void> _fetchDeletedBookings() async {
    final snapshot = await _deletedBookingsRef.once();
    final data = snapshot.snapshot.value as Map<dynamic, dynamic>?;

    if (data != null) {
      setState(() {
        deletedBookings = data.entries.map((entry) {
          final value = entry.value as Map<dynamic, dynamic>;
          return {
            'id': entry.key,
            'borrower_name': value['borrower_name'],
            'book_title': value['book_title'],
            'borrow_date': value['borrow_date'],
            'return_date': value['return_date'],
            'status': value['status'],
          };
        }).toList();
      });
    }
  }

  Future<void> _updateBookingStatus(String bookingId, String newStatus) async {
    await _bookingsRef.child(bookingId).update({'status': newStatus});
    await _fetchBookings();
  }

  Future<void> _temporaryDeleteBooking(String bookingId) async {
    try {
      final booking = bookings.firstWhere((b) => b['id'] == bookingId);

      // Store the current status before moving to temporary delete
      booking['previous_status'] = booking['status'];

      // Move to temporary delete
      await _tempDeletedRef.child(bookingId).set(booking);
      await _bookingsRef
          .child(bookingId)
          .update({'status': 'temporary_delete'});

      setState(() {
        bookings.removeWhere((b) => b['id'] == bookingId);
        temporaryDeletedBookings.add(booking);
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Item moved to Temporary Delete')),
        );
      }
    } catch (e) {
      print('Error moving to temporary delete: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to delete item')),
        );
      }
    }
  }

  Future<void> _temporaryDeleteSelectedBookings(String role) async {
    try {
      final selectedBookings =
          role == 'student' ? selectedStudentBookings : selectedStaffBookings;

      for (var bookingId in selectedBookings) {
        final booking = bookings.firstWhere((b) => b['id'] == bookingId);

        // Store the current status before moving to temporary delete
        booking['previous_status'] = booking['status'];

        // Move to temporary delete
        await _tempDeletedRef.child(bookingId).set(booking);
        await _bookingsRef
            .child(bookingId)
            .update({'status': 'temporary_delete'});

        setState(() {
          bookings.removeWhere((b) => b['id'] == bookingId);
          temporaryDeletedBookings.add(booking);
        });
      }

      // Clear selections based on role
      setState(() {
        if (role == 'student') {
          selectedStudentBookings.clear();
          isSelectAllStudent = false;
        } else {
          selectedStaffBookings.clear();
          isSelectAllStaff = false;
        }
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '${selectedBookings.length} items moved to Temporary Delete'),
          ),
        );
      }
    } catch (e) {
      print('Error moving to temporary delete: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to delete selected items')),
        );
      }
    }
  }

  Future<void> _restoreDeletedBooking(String bookingId) async {
    final booking =
        deletedBookings.firstWhere((booking) => booking['id'] == bookingId);

    // Restore from deleted bookings to bookings
    await _bookingsRef.child(bookingId).set(booking);
    await _deletedBookingsRef.child(bookingId).remove();
    setState(() {
      deletedBookings.removeWhere((booking) => booking['id'] == bookingId);
      bookings.add(booking);
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Booking restored successfully')),
    );
  }

  Future<void> _permanentlyDeleteBooking(String bookingId) async {
    await _deletedBookingsRef.child(bookingId).remove();
    await _bookingsRef
        .child(bookingId)
        .remove(); // Remove from bookings as well
    setState(() {
      deletedBookings.removeWhere((booking) => booking['id'] == bookingId);
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Booking permanently deleted')),
    );
  }

  Future<void> _permanentlyDeleteSelectedBookings() async {
    for (var bookingId in selectedBookings) {
      await _deletedBookingsRef.child(bookingId).remove();
      await _bookingsRef.child(bookingId).remove(); // Remove from bookings
      setState(() {
        deletedBookings.removeWhere((booking) => booking['id'] == bookingId);
      });
    }

    selectedBookings.clear();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Selected bookings permanently deleted')),
    );
  }

  void _toggleSelectAllStudent() {
    setState(() {
      isSelectAllStudent = !isSelectAllStudent;
      if (isSelectAllStudent) {
        // Select all student bookings with specific statuses
        selectedStudentBookings = bookings
            .where((booking) =>
                booking['role']?.toString().toLowerCase() == 'student' &&
                (booking['status'] == 'Pending' ||
                    booking['status'] == 'Approved' ||
                    booking['status'] == 'Rejected'))
            .map((booking) => booking['id'].toString())
            .toList();
      } else {
        selectedStudentBookings.clear();
      }
    });
  }

  void _toggleSelectAllStaff() {
    setState(() {
      isSelectAllStaff = !isSelectAllStaff;
      if (isSelectAllStaff) {
        // Select all staff bookings with specific statuses
        selectedStaffBookings = bookings
            .where((booking) =>
                booking['role']?.toString().toLowerCase() == 'staff' &&
                (booking['status'] == 'Pending' ||
                    booking['status'] == 'Approved' ||
                    booking['status'] == 'Rejected'))
            .map((booking) => booking['id'].toString())
            .toList();
      } else {
        selectedStaffBookings.clear();
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _fetchBookings();
    _fetchDeletedBookings();
    _fetchTemporaryDeletedBookings();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Widget _buildBookingList(List<Map<String, dynamic>> bookings, String role) {
    return bookings.isEmpty
        ? const Center(child: Text('No bookings available.'))
        : Column(
            children: bookings.map((booking) {
              final isSelected = role == 'student'
                  ? selectedStudentBookings.contains(booking['id'])
                  : selectedStaffBookings.contains(booking['id']);

              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                elevation: 3,
                child: ListTile(
                  leading: Checkbox(
                    value: isSelected,
                    onChanged: (bool? value) {
                      setState(() {
                        if (role == 'student') {
                          if (value == true) {
                            selectedStudentBookings.add(booking['id']);
                          } else {
                            selectedStudentBookings.remove(booking['id']);
                          }
                        } else {
                          if (value == true) {
                            selectedStaffBookings.add(booking['id']);
                          } else {
                            selectedStaffBookings.remove(booking['id']);
                          }
                        }
                      });
                    },
                  ),
                  contentPadding: const EdgeInsets.all(10),
                  title: Text(
                    booking['book_title'] ?? 'No book title',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Borrower: ${booking['borrower_name']}'),
                      Text('Borrow Date: ${booking['borrow_date']}'),
                      Text('Return Date: ${booking['return_date']}'),
                      Text('Status: ${booking['status']}'),
                    ],
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (booking['status'] == 'Pending') ...[
                        IconButton(
                          icon: const Icon(Icons.check_circle_outline),
                          color: Colors.green,
                          onPressed: () =>
                              _updateBookingStatus(booking['id'], 'Approved'),
                          tooltip: 'Approve',
                        ),
                        IconButton(
                          icon: const Icon(Icons.cancel_outlined),
                          color: Colors.red,
                          onPressed: () =>
                              _updateBookingStatus(booking['id'], 'Rejected'),
                          tooltip: 'Reject',
                        ),
                      ],
                      if (booking['status'] == 'Approved' ||
                          booking['status'] == 'Rejected')
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          color: Colors.red,
                          onPressed: () =>
                              _temporaryDeleteBooking(booking['id']),
                          tooltip: 'Move to Temporary Delete',
                        ),
                    ],
                  ),
                ),
              );
            }).toList(),
          );
  }

  @override
  Widget build(BuildContext context) {
    // Filter bookings by role
    final studentBookings = bookings.where((booking) {
      final role = booking['role']?.toString().toLowerCase() ?? '';
      print("Checking booking role: $role"); // Debug print role
      return role == 'student';
    }).toList();

    final staffBookings = bookings.where((booking) {
      final role = booking['role']?.toString().toLowerCase() ?? '';
      print("Checking booking role: $role"); // Debug print role
      return role == 'staff';
    }).toList();

    print(
        "Student bookings count: ${studentBookings.length}"); // Debug print counts
    print("Staff bookings count: ${staffBookings.length}");

    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin - Book Lending'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => Navigator.of(context).pushReplacementNamed('/'),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Student Requests'),
            Tab(text: 'Staff Requests'),
            Tab(text: 'Temporary Delete'),
            Tab(text: 'Delete History'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Tab 1: Student Requests
          _buildStudentRequestsTab(),
          // Tab 2: Staff Requests
          _buildStaffRequestsTab(),
          // Tab 3: Temporary Delete
          _buildTemporaryDeleteTab(),
          // Tab 4: Delete History
          SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Delete History',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
                ),
                const SizedBox(height: 16),
                _buildDeleteHistoryList(deletedBookings),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStudentRequestsTab() {
    // Filter student bookings to only show specific statuses
    final studentBookings = bookings
        .where((booking) =>
            booking['role']?.toString().toLowerCase() == 'student' &&
            (booking['status'] == 'Pending' ||
                booking['status'] == 'Approved' ||
                booking['status'] == 'Rejected'))
        .toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Student Requests',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Checkbox(
                value: isSelectAllStudent,
                onChanged: (_) => _toggleSelectAllStudent(),
              ),
              const Text("Select All"),
              const Spacer(),
              ElevatedButton(
                onPressed: selectedStudentBookings.isEmpty
                    ? null
                    : () => _temporaryDeleteSelectedBookings('student'),
                child: const Text('Move to Temporary Delete'),
              ),
            ],
          ),
          _buildBookingList(studentBookings, 'student'),
        ],
      ),
    );
  }

  Widget _buildStaffRequestsTab() {
    // Filter staff bookings to only show specific statuses
    final staffBookings = bookings
        .where((booking) =>
            booking['role']?.toString().toLowerCase() == 'staff' &&
            (booking['status'] == 'Pending' ||
                booking['status'] == 'Approved' ||
                booking['status'] == 'Rejected'))
        .toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Staff Requests',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Checkbox(
                value: isSelectAllStaff,
                onChanged: (_) => _toggleSelectAllStaff(),
              ),
              const Text("Select All"),
              const Spacer(),
              ElevatedButton(
                onPressed: selectedStaffBookings.isEmpty
                    ? null
                    : () => _temporaryDeleteSelectedBookings('staff'),
                child: const Text('Move to Temporary Delete'),
              ),
            ],
          ),
          _buildBookingList(staffBookings, 'staff'),
        ],
      ),
    );
  }

  Widget _buildTemporaryDeleteTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Checkbox(
                value: isSelectAllTempDelete,
                onChanged: (bool? value) {
                  setState(() {
                    isSelectAllTempDelete = value ?? false;
                    if (isSelectAllTempDelete) {
                      selectedTempDeletedBookings = temporaryDeletedBookings
                          .map((booking) => booking['id'].toString())
                          .toList();
                    } else {
                      selectedTempDeletedBookings.clear();
                    }
                  });
                },
              ),
              const Text("Select All"),
              const Spacer(),
              ElevatedButton(
                onPressed: selectedTempDeletedBookings.isEmpty
                    ? null
                    : _showBulkDeleteConfirmationDialog,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                ),
                child: const Text('Permanently Delete Selected'),
              ),
            ],
          ),
        ),
        Expanded(
          child: _buildTemporaryDeletedList(),
        ),
      ],
    );
  }

  Future<void> _restoreBooking(String bookingId) async {
    try {
      final booking =
          temporaryDeletedBookings.firstWhere((b) => b['id'] == bookingId);
      await _bookingsRef
          .child(bookingId)
          .update({'status': booking['previous_status'] ?? 'Pending'});
      await _tempDeletedRef.child(bookingId).remove();

      setState(() {
        temporaryDeletedBookings.removeWhere((b) => b['id'] == bookingId);
        bookings.add(booking);
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Booking restored successfully')),
        );
      }
    } catch (e) {
      print('Error restoring booking: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to restore booking')),
        );
      }
    }
  }

  bool isSelectAllTempDelete = false;
  List<String> selectedTempDeletedBookings = [];

  Future<void> _permanentlyDeleteAndMoveToHistory(String bookingId) async {
    try {
      final booking =
          temporaryDeletedBookings.firstWhere((b) => b['id'] == bookingId);

      // Add deletion date to the booking record
      booking['deleted_date'] = DateTime.now().toIso8601String();

      // Move to delete history
      await _deletedBookingsRef.child(bookingId).set(booking);
      // Remove from temporary delete
      await _tempDeletedRef.child(bookingId).remove();
      // Remove from main bookings
      await _bookingsRef.child(bookingId).remove();

      setState(() {
        temporaryDeletedBookings.removeWhere((b) => b['id'] == bookingId);
        deletedBookings.add(booking);
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Item permanently deleted and moved to history'),
            backgroundColor: Colors.green, // Success color
            duration: Duration(seconds: 2), // Show for 2 seconds
          ),
        );
      }
    } catch (e) {
      print('Error permanently deleting: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to permanently delete item'),
            backgroundColor: Colors.red, // Error color
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _permanentlyDeleteSelectedAndMoveToHistory() async {
    try {
      for (var bookingId in selectedTempDeletedBookings) {
        final booking =
            temporaryDeletedBookings.firstWhere((b) => b['id'] == bookingId);

        await _deletedBookingsRef.child(bookingId).set(booking);
        await _tempDeletedRef.child(bookingId).remove();
        await _bookingsRef.child(bookingId).remove();

        setState(() {
          temporaryDeletedBookings.removeWhere((b) => b['id'] == bookingId);
          deletedBookings.add(booking);
        });
      }

      final itemCount = selectedTempDeletedBookings.length;
      selectedTempDeletedBookings.clear();
      isSelectAllTempDelete = false;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '$itemCount items permanently deleted and moved to history'),
            backgroundColor: Colors.green, // Success color
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      print('Error permanently deleting items: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to permanently delete selected items'),
            backgroundColor: Colors.red, // Error color
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _fetchTemporaryDeletedBookings() async {
    final snapshot = await _tempDeletedRef.once();
    if (snapshot.snapshot.value != null) {
      final data = snapshot.snapshot.value as Map<dynamic, dynamic>;
      setState(() {
        temporaryDeletedBookings = data.entries.map((entry) {
          final value = entry.value as Map<dynamic, dynamic>;
          return {
            'id': entry.key,
            'borrower_name': value['borrower_name'],
            'book_title': value['book_title'],
            'borrow_date': value['borrow_date'],
            'return_date': value['return_date'],
            'status': value['status'],
            'previous_status': value['previous_status'],
          };
        }).toList();
      });
    }
  }

  Widget _buildTemporaryDeletedList() {
    return temporaryDeletedBookings.isEmpty
        ? const Center(child: Text('No temporarily deleted bookings.'))
        : ListView.builder(
            padding: const EdgeInsets.all(16.0),
            itemCount: temporaryDeletedBookings.length,
            itemBuilder: (context, index) {
              final booking = temporaryDeletedBookings[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 8.0),
                child: ListTile(
                  leading: Checkbox(
                    value: selectedTempDeletedBookings.contains(booking['id']),
                    onChanged: (bool? value) {
                      setState(() {
                        if (value == true) {
                          selectedTempDeletedBookings.add(booking['id']);
                        } else {
                          selectedTempDeletedBookings.remove(booking['id']);
                        }
                      });
                    },
                  ),
                  title: Text(booking['book_title'] ?? 'No book title'),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Borrower: ${booking['borrower_name']}'),
                      Text('Borrow Date: ${booking['borrow_date']}'),
                      Text('Return Date: ${booking['return_date']}'),
                      Text('Previous Status: ${booking['previous_status']}'),
                    ],
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.restore),
                        color: Colors.green,
                        onPressed: () => _restoreBooking(booking['id']),
                        tooltip: 'Restore',
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_forever),
                        color: Colors.red,
                        onPressed: () =>
                            _showDeleteConfirmationDialog(booking['id']),
                        tooltip: 'Permanently Delete',
                      ),
                    ],
                  ),
                ),
              );
            },
          );
  }

  // Create a separate method for the Delete History list
  Widget _buildDeleteHistoryList(List<Map<String, dynamic>> deletedBookings) {
    return deletedBookings.isEmpty
        ? const Center(child: Text('No deleted bookings in history.'))
        : ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: deletedBookings.length,
            itemBuilder: (context, index) {
              final booking = deletedBookings[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 8.0),
                child: ListTile(
                  contentPadding: const EdgeInsets.all(16.0),
                  title: Text(
                    booking['book_title'] ?? 'No book title',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Borrower: ${booking['borrower_name']}'),
                      Text('Borrow Date: ${booking['borrow_date']}'),
                      Text('Return Date: ${booking['return_date']}'),
                      Text('Previous Status: ${booking['previous_status']}'),
                      Text(
                          'Deleted Date: ${booking['deleted_date'] ?? 'Not recorded'}'),
                    ],
                  ),
                ),
              );
            },
          );
  }

  // Add confirmation dialog before permanent deletion
  Future<void> _showDeleteConfirmationDialog(String bookingId) async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false, // User must tap button to close dialog
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Confirm Permanent Deletion'),
          content: const SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                Text('Are you sure you want to permanently delete this item?'),
                Text(
                  'This action cannot be undone.',
                  style: TextStyle(color: Colors.red),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: const Text(
                'Delete Permanently',
                style: TextStyle(color: Colors.red),
              ),
              onPressed: () {
                Navigator.of(context).pop();
                _permanentlyDeleteAndMoveToHistory(bookingId);
              },
            ),
          ],
        );
      },
    );
  }

  // Add confirmation dialog for bulk deletion
  Future<void> _showBulkDeleteConfirmationDialog() async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Confirm Bulk Permanent Deletion'),
          content: SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                Text(
                    'Are you sure you want to permanently delete ${selectedTempDeletedBookings.length} items?'),
                const Text(
                  'This action cannot be undone.',
                  style: TextStyle(color: Colors.red),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: const Text(
                'Delete Permanently',
                style: TextStyle(color: Colors.red),
              ),
              onPressed: () {
                Navigator.of(context).pop();
                _permanentlyDeleteSelectedAndMoveToHistory();
              },
            ),
          ],
        );
      },
    );
  }
}
