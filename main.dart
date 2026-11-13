import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart'; // Librería para acceder al GPS y obtener la ubicación del dispositivo
import 'package:http/http.dart' as http;

void main() {
  runApp(const MyApp()); //<-- Inicia la aplicación y dibuja la pantalla MyApp
}

// ------- Cambia esta URL por la IP de tu servidor FastAPI ------- //
const String baseUrl = "http://localhost:8000";

// ------- CLASE MyApp Configuración general de la aplicación ------- //
class MyApp extends StatelessWidget {
  //<--La pantalla no cambia (No guarda los datos que se modifiquen)
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      //<-- Diseña el widget: Retornando lo que se mostrara en la pantalla
      debugShowCheckedModeBanner: false,
      title: 'Pase de Lista GPS', //<-- Nombre de la app
      theme: ThemeData(primarySwatch: Colors.blue), //<-- Tema
      home: const LoginScreen(), //<-- Primera pantalla se muestra: Login
    );
  }
}

// --------------- PANTALLA DE LOGIN Y REGISTRO ---------------- //
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _userController = TextEditingController();
  final TextEditingController _passController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _userController.dispose();
    _passController.dispose();
    super.dispose();
  }

  Future<void> _authenticate(String endpoint) async {
    setState(() => _isLoading = true);
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/$endpoint/'),
        headers: {"Content-Type": "application/json"},
        body: json.encode({
          "username": _userController.text.trim(),
          "password": _passController.text.trim(),
        }),
      );

      final data = json.decode(utf8.decode(response.bodyBytes));

      if (response.statusCode == 200) {
        if (!mounted) return;
        Navigator.pushReplacement(
          //<---Flecha de regreso (Parte superior)
          context,
          MaterialPageRoute(
            builder: (context) => AttendanceScreen(userId: data['user_id']),
          ),
        );
      } else {
        _showMessage(data['detail'] ?? 'Error de autenticación');
      }
    } catch (e) {
      _showMessage('Error de conexión con el servidor');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showMessage(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Acceso al Sistema')),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(
              controller: _userController,
              decoration: const InputDecoration(labelText: 'Usuario'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _passController,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Contraseña'),
            ),
            const SizedBox(height: 24),
            if (_isLoading)
              const CircularProgressIndicator()
            else
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton(
                    onPressed: () => _authenticate('login'),
                    child: const Text('Iniciar Sesión'),
                  ),
                  OutlinedButton(
                    onPressed: () => _authenticate('register'),
                    child: const Text('Registrarse'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

// --- PANTALLA PRINCIPAL DE ASISTENCIA ---
class AttendanceScreen extends StatefulWidget {
  final int userId;
  const AttendanceScreen({super.key, required this.userId});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  String _address = "";
  bool _isLoading = false;

  Future<Position> _determinePosition() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw Exception('Los servicios de ubicación están desactivados.');
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw Exception('Permisos de ubicación denegados.');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      throw Exception('Permisos denegados permanentemente.');
    }

    return await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
  }

  Future<void> _registerAttendance() async {
    setState(() => _isLoading = true);
    try {
      Position position = await _determinePosition();

      final response = await http.post(
        Uri.parse('$baseUrl/attendance/'),
        headers: {"Content-Type": "application/json"},
        body: json.encode({
          "user_id": widget.userId,
          "latitude": position.latitude,
          "longitude": position.longitude,
        }),
      );

      final data = json.decode(utf8.decode(response.bodyBytes));

      if (response.statusCode == 200) {
        if (!mounted) return;
        setState(() {
          _address = data['address'];
        });
      } else {
        _showError(data['detail'] ?? 'No se pudo registrar la asistencia');
      }
    } catch (e) {
      _showError(e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEAF1FB),
      appBar: AppBar(
        title: const Text('Registro de Asistencia'),
        backgroundColor: const Color(0xFF28589C),
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton.icon(
                onPressed: _isLoading ? null : _registerAttendance,
                icon: const Icon(Icons.location_on, color: Colors.white),
                label: Text(
                  _isLoading
                      ? 'Obteniendo ubicación...'
                      : 'Registrar asistencia',
                  style: const TextStyle(fontSize: 16, color: Colors.white),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF23478A),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              //1. -----BOTON : MOSTRAR EL HISTORIAL-------------//
              OutlinedButton.icon(
                //<--Crea un boton(Con un icono y texto)
                onPressed: () {
                  Navigator.push(
                    //<--- abre una pantalla nueva encima de la actual
                    context,
                    MaterialPageRoute(
                      //<--- Define la pantalla que abre, en este caso HistoryScreen
                      builder: (context) => HistoryScreen(userId: widget.userId), //<--Id del usuario que inicio sesion -Lo pasamos a HistoryScreen para pedir sus asistencias
                    ),
                  );
                },
                icon: const Icon(Icons.history),
                label: const Text('Ver historial'),
              ),
              const SizedBox(height: 16),
              //-------------------------------------------------//

              if (_address.isNotEmpty)
                Card(
                  elevation: 3,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text(
                      "📍 $_address",
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 15, height: 1.4),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

//1. --------- MODELO: Ficha de regsitro de una Asistencia ----------//
class AttendanceRecord {
  final String address; //final:Una vez asignado no cambiaran
  final double latitude;
  final double longitude;
  final String createdAt; //<--Fecha y hora de regsitro

  //constructor: Crea la ficha
  //Guarda lo que recibe en cada uno de sus campos
  AttendanceRecord({
    required this.address,
    required this.latitude,
    required this.longitude,
    required this.createdAt,
  });

  //Crea un objeto a partir del JSON
  factory AttendanceRecord.fromJson(Map<String, dynamic> json) {
    //Retorna un ficha nueva
    return AttendanceRecord(
      address: json['address'] ?? 'Sin direccion', //Busca en el JSON el dato "address" y lo guarda en el campo "address" - ??: si no existe usa el mensaje  'Sin direccion'
      latitude: (json['latitude'] ?? 0).toDouble(), //Busca 'latitud'. Si no existe, usa 0. '.toDouble' lo convierte en decimal
      longitude: (json['longitude'] ?? 0).toDouble(), //Busca 'longitud'. Si no existe, usa 0. '.toDouble' lo convierte en decimal
      createdAt:
          json['created_at'] ??
          '', //Busca 'created_at'. Si no existe, usa un texto vacio
    );
  }
}

// --- PANTALLA DE HISTORIAL DE ASISTENCIAS ---
class HistoryScreen extends StatefulWidget {
  //Recibe el 'id' del usuario
  final int userId;

  //Constructor: Pide el 'userid' obligatoriamente.
  const HistoryScreen({super.key, required this.userId});

  //Conceta la Primera Clase con la Segunda Clase
  @override
  State<HistoryScreen> createState() => _HistoryScreenState(); //clase 1: Guarda los datos que recibe owo - clase2: Logica
}

//Define la clase2 como privada '_'
class _HistoryScreenState extends State<HistoryScreen> {
  late Future<List<AttendanceRecord>> _futureRecords;

  @override
  void initState() {
    //<--Funcion que "se ejecuta una sola vez"
    super.initState();
    _futureRecords = _fetchHistory(); // pide los datos al abrir la pantalla
  }

  //Define que es una ficha,  'List<..>': Es una lista de fichas - 'Future<..>: Lista que "llegara mas tarde"' - 'late': Le dara e valor despues, no ahora
  Future<List<AttendanceRecord>> _fetchHistory() async {
    final response = await http.get(
      Uri.parse('$baseUrl/attendance/?user_id=${widget.userId}'),
    );

    if (response.statusCode != 200) {
      throw Exception('No se pudo cargar el historial');
    }

    final List<dynamic> data = json.decode(utf8.decode(response.bodyBytes));
    return data.map((item) => AttendanceRecord.fromJson(item)).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEAF1FB),
      appBar: AppBar(
        title: const Text('Historial de Asistencias'),
        backgroundColor: const Color(0xFF28589C),
        foregroundColor: Colors.white,
      ),
      body: FutureBuilder<List<AttendanceRecord>>(
        future: _futureRecords,
        builder: (context, snapshot) {
          // 1. Cargando
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          // 2. Error
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          // 3. Sin datos
          final records = snapshot.data ?? [];
          if (records.isEmpty) {
            return const Center(
              child: Text('Aún no hay asistencias registradas'),
            );
          }
          // 4. Lista de registros
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: records.length,
            itemBuilder: (context, index) {
              final record = records[index];
              return Card(
                elevation: 3,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ListTile(
                  leading: const Icon(
                    Icons.location_on,
                    color: Color(0xFF23478A),
                  ),
                  title: Text(record.address),
                  subtitle: Text(record.createdAt),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
