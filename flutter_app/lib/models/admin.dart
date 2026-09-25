/// The signed-in kiosk admin. The password is never kept — only the identity
/// returned by HRMS (the bearer token lives in [AppState] / SharedPreferences).
class Admin {
  final String name;
  final String email;
  final String? id;

  const Admin({required this.name, required this.email, this.id});
}
