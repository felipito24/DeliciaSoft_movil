import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../services/cart_services.dart';
import '../providers/auth_provider.dart';

class CheckoutScreen extends StatefulWidget {
  final int clientId;

  const CheckoutScreen({super.key, required this.clientId});

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  final _formKey = GlobalKey<FormState>();
  final _observacionesController = TextEditingController();
  final _mensajeController = TextEditingController();
  final _abonoController = TextEditingController();
  
  List<dynamic> _sedes = [];
  int? _sedeSeleccionada;
  DateTime? _fechaEntrega;
  String _metodoPago = 'Efectivo';
  File? _comprobanteImagen;
  bool _isLoading = false;
  bool _isLoadingSedes = true;
  double _totalPedido = 0;

  String _formatPrice(double price) {
    final priceStr = price.toStringAsFixed(0);
    return priceStr.replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]}.',
    );
  }

  String _formatNumberForDisplay(double number) {
    return number.toStringAsFixed(0).replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]}.',
    );
  }

  String _formatDateForAPI(DateTime date) {
    String pad(int n) => n.toString().padLeft(2, '0');
    return '${date.year}-${pad(date.month)}-${pad(date.day)}T${pad(date.hour)}:${pad(date.minute)}:${pad(date.second)}';
  }

  @override
  void initState() {
    super.initState();
    _cargarSedes();
    _calcularTotal();
  }

  void _calcularTotal() {
    final cartService = Provider.of<CartService>(context, listen: false);
    setState(() {
      _totalPedido = cartService.total;
      _abonoController.text = _formatNumberForDisplay(_totalPedido * 0.5);
    });
  }

  Future<void> _cargarSedes() async {
    setState(() => _isLoadingSedes = true);
    try {
      final response = await http.get(
        Uri.parse('https://deliciasoft-backend-i6g9.onrender.com/api/sede'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          throw Exception('Tiempo de espera agotado');
        },
      );
      
      if (response.statusCode == 200) {
        final dynamic responseData = json.decode(response.body);
        List<dynamic> sedes = [];
        
        if (responseData is List) {
          sedes = responseData;
        } else if (responseData is Map) {
          if (responseData.containsKey('data')) {
            sedes = responseData['data'] as List;
          } else if (responseData.containsKey('sedes')) {
            sedes = responseData['sedes'] as List;
          } else if (responseData.containsKey('result')) {
            sedes = responseData['result'] as List;
          }
        }
        
        if (mounted) {
          setState(() {
            _sedes = sedes;
            _isLoadingSedes = false;
            if (_sedes.isNotEmpty) {
              final dynamic primeraSedeId = _sedes[0]['idsede'] ?? _sedes[0]['idSede'] ?? _sedes[0]['id'];
              if (primeraSedeId != null) {
                _sedeSeleccionada = primeraSedeId is int ? primeraSedeId : int.tryParse(primeraSedeId.toString());
              }
            }
          });
        }
        
        if (_sedes.isEmpty) {
          _mostrarMensaje('No hay sedes disponibles en este momento', Colors.orange);
        }
      } else {
        throw Exception('Error del servidor: ${response.statusCode}');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingSedes = false);
        _mostrarMensaje(
          'No se pudieron cargar las sedes. Verifica tu conexión.',
          Colors.red,
        );
      }
    }
  }

  Future<void> _seleccionarFecha() async {
    final DateTime ahora = DateTime.now();
    final DateTime minFecha = ahora.add(const Duration(days: 15));
    final DateTime maxFecha = ahora.add(const Duration(days: 30));
    
    try {
      final DateTime? picked = await showDatePicker(
        context: context,
        initialDate: _fechaEntrega ?? minFecha,
        firstDate: minFecha,
        lastDate: maxFecha,
        builder: (context, child) {
          return Theme(
            data: Theme.of(context).copyWith(
              colorScheme: ColorScheme.light(
                primary: Colors.pink[400]!,
                onPrimary: Colors.white,
                surface: Colors.white,
                onSurface: Colors.black,
              ),
              dialogBackgroundColor: Colors.white,
            ),
            child: child!,
          );
        },
        helpText: 'Seleccionar fecha de entrega',
        cancelText: 'Cancelar',
        confirmText: 'Aceptar',
      );
      
      if (picked != null) {
        setState(() => _fechaEntrega = picked);
      }
    } catch (e) {
      _mostrarMensaje('Error al abrir calendario', Colors.red);
    }
  }

  Future<void> _seleccionarComprobante() async {
    final ImagePicker picker = ImagePicker();
    try {
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );
      if (image != null) {
        setState(() => _comprobanteImagen = File(image.path));
      }
    } catch (e) {
      _mostrarMensaje('Error al seleccionar imagen: $e', Colors.red);
    }
  }

// 🔥 REEMPLAZA SOLO LA FUNCIÓN _procesarPedido() EN checkout_screen.dart

Future<void> _procesarPedido() async {
  if (!_formKey.currentState!.validate()) return;
  
  final cartService = Provider.of<CartService>(context, listen: false);
  
  int totalProductos = cartService.items.fold(0, (sum, item) => sum + item.cantidad);
  if (totalProductos < 10) {
    _mostrarMensaje(
      'Debes tener mínimo 10 productos en tu carrito. Actualmente tienes $totalProductos.',
      Colors.orange,
    );
    return;
  }
  
  if (_sedeSeleccionada == null) {
    _mostrarMensaje('Selecciona una sede para recoger', Colors.orange);
    return;
  }
  if (_fechaEntrega == null) {
    _mostrarMensaje('Selecciona una fecha de entrega', Colors.orange);
    return;
  }
  
  String abonoText = _abonoController.text.replaceAll('.', '').replaceAll(',', '');
  final double abonoIngresado = double.tryParse(abonoText) ?? 0;
  final double minimoAbono = _totalPedido * 0.5;
  
  if (abonoIngresado < minimoAbono) {
    _mostrarMensaje('El abono mínimo es del 50%: \$${_formatPrice(minimoAbono)}', Colors.orange);
    return;
  }
  
  if (_metodoPago == 'Transferencia' && _comprobanteImagen == null) {
    _mostrarMensaje('Debes subir el comprobante de transferencia', Colors.orange);
    return;
  }
  
  setState(() => _isLoading = true);
  
  try {
    final DateTime fechaEntregaConHora = DateTime(
      _fechaEntrega!.year,
      _fechaEntrega!.month,
      _fechaEntrega!.day,
      12,
      0,
      0,
    );

    final pedidoData = {
      'idcliente': widget.clientId,
      'idsede': _sedeSeleccionada,
      'fechapedido': _formatDateForAPI(DateTime.now()),
      'fechaentrega': _formatDateForAPI(fechaEntregaConHora),
      'total': _totalPedido,
      'estado': 'Pendiente',
      'observaciones': _observacionesController.text.trim().isEmpty ? '' : _observacionesController.text.trim(),
      'mensajepersonalizado': _mensajeController.text.trim().isEmpty ? '' : _mensajeController.text.trim(),
    };

    print('📦 ======================================== INICIO');
    print('📦 CREANDO PEDIDO');
    print('📦 URL: https://deliciasoft-backend-i6g9.onrender.com/api/pedido');
    print('📦 ========================================');
    print('📦 DATOS ENVIADOS:');
    print(json.encode(pedidoData));
    print('📦 ========================================');

    final pedidoResponse = await http.post(
      Uri.parse('https://deliciasoft-backend-i6g9.onrender.com/api/pedido'),
      headers: {'Content-Type': 'application/json; charset=UTF-8'},
      body: json.encode(pedidoData),
    ).timeout(
      const Duration(seconds: 30),
      onTimeout: () => throw Exception('Tiempo de espera agotado al crear pedido'),
    );

    print('📦 ========================================');
    print('📦 RESPUESTA DEL SERVIDOR');
    print('📦 Status Code: ${pedidoResponse.statusCode}');
    print('📦 ========================================');
    print('📦 BODY COMPLETO:');
    print(pedidoResponse.body);
    print('📦 ========================================');

    if (pedidoResponse.statusCode != 200 && pedidoResponse.statusCode != 201) {
      throw Exception('Error al crear pedido: ${pedidoResponse.body}');
    }

    // 🔥 PARSEAR RESPUESTA
    final dynamic respuesta = json.decode(pedidoResponse.body);
    
    print('📦 ========================================');
    print('📦 ANÁLISIS DE RESPUESTA');
    print('📦 Tipo: ${respuesta.runtimeType}');
    
    // 🔥 EXTRAER TODOS LOS POSIBLES IDs
    int? idPedido;
    int? idVenta;
    
    if (respuesta is Map) {
      print('📦 Es un Map, buscando IDs...');
      print('📦 Claves disponibles: ${respuesta.keys.toList()}');
      
      // Buscar en nivel raíz
      if (respuesta.containsKey('idpedido')) {
        idPedido = respuesta['idpedido'] is int ? respuesta['idpedido'] : int.tryParse(respuesta['idpedido'].toString());
        print('📦 idpedido (raíz): $idPedido');
      }
      if (respuesta.containsKey('idventa')) {
        idVenta = respuesta['idventa'] is int ? respuesta['idventa'] : int.tryParse(respuesta['idventa'].toString());
        print('📦 idventa (raíz): $idVenta');
      }
      
      // Buscar en 'data'
      if (respuesta.containsKey('data') && respuesta['data'] is Map) {
        final data = respuesta['data'] as Map;
        print('📦 Encontrado objeto "data", claves: ${data.keys.toList()}');
        
        if (idPedido == null && data.containsKey('idpedido')) {
          idPedido = data['idpedido'] is int ? data['idpedido'] : int.tryParse(data['idpedido'].toString());
          print('📦 idpedido (data): $idPedido');
        }
        if (idVenta == null && data.containsKey('idventa')) {
          idVenta = data['idventa'] is int ? data['idventa'] : int.tryParse(data['idventa'].toString());
          print('📦 idventa (data): $idVenta');
        }
      }
      
      // Buscar en 'pedido'
      if (respuesta.containsKey('pedido') && respuesta['pedido'] is Map) {
        final pedido = respuesta['pedido'] as Map;
        print('📦 Encontrado objeto "pedido", claves: ${pedido.keys.toList()}');
        
        if (idPedido == null && pedido.containsKey('idpedido')) {
          idPedido = pedido['idpedido'] is int ? pedido['idpedido'] : int.tryParse(pedido['idpedido'].toString());
          print('📦 idpedido (pedido): $idPedido');
        }
        if (idVenta == null && pedido.containsKey('idventa')) {
          idVenta = pedido['idventa'] is int ? pedido['idventa'] : int.tryParse(pedido['idventa'].toString());
          print('📦 idventa (pedido): $idVenta');
        }
      }
    }
    
    print('📦 ========================================');
    print('📦 IDs EXTRAÍDOS FINALES:');
    print('📦 idPedido = $idPedido');
    print('📦 idVenta = $idVenta');
    print('📦 ========================================');

    // 🔥 VALIDACIÓN CRÍTICA
    if (idVenta == null && idPedido == null) {
      throw Exception('❌ No se pudo extraer ningún ID de la respuesta del servidor');
    }

  

    final int idParaAbono = idVenta ?? idPedido!;
    
    print('💰 ========================================');
    print('💰 PREPARANDO ABONO');
    print('💰 ========================================');
    print('💰 ID que se usará: $idParaAbono (${idVenta != null ? "es idVenta" : "es idPedido"})');
    print('💰 Método de pago: $_metodoPago');
    print('💰 Cantidad a pagar: $abonoIngresado');
    print('💰 ========================================');

 // 🔥 CREAR ABONO
bool abonoExitoso = false;
String mensajeErrorAbono = '';

try {
  if (_metodoPago == 'Efectivo') {
    print('💰 MÉTODO: EFECTIVO (application/json)');

    final abonoData = {
      'idpedido': idParaAbono,
      'metodopago': _metodoPago,
      'cantidadpagar': abonoIngresado,
      'TotalPagado': abonoIngresado,
    };

    print('💰 ========================================');
    print('💰 DATOS JSON PARA ABONO:');
    print(json.encode(abonoData));
    print('💰 ========================================');

    final abonoResponse = await http.post(
      Uri.parse('https://deliciasoft-backend-i6g9.onrender.com/api/abonos'),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: json.encode(abonoData),
    ).timeout(
      const Duration(seconds: 30),
      onTimeout: () => throw Exception('Timeout al crear abono'),
    );

    print('💰 ========================================');
    print('💰 RESPUESTA ABONO');
    print('💰 Status: ${abonoResponse.statusCode}');
    print('💰 ========================================');
    print('💰 Body:');
    print(abonoResponse.body);
    print('💰 ========================================');

    if (abonoResponse.statusCode == 200 || abonoResponse.statusCode == 201) {
      print('✅ ABONO CREADO EXITOSAMENTE');
      abonoExitoso = true;
    } else {
      print('⚠️ ERROR AL CREAR ABONO');
      mensajeErrorAbono = 'Status: ${abonoResponse.statusCode}, Body: ${abonoResponse.body}';
    }

  } else if (_metodoPago == 'Transferencia') {
    print('💰 MÉTODO: TRANSFERENCIA (multipart/form-data)');

    var abonoRequest = http.MultipartRequest(
      'POST',
      Uri.parse('https://deliciasoft-backend-i6g9.onrender.com/api/abonos'),
    );

    abonoRequest.headers['Accept'] = 'application/json';

    abonoRequest.fields['idpedido'] = idParaAbono.toString();
    abonoRequest.fields['metodopago'] = _metodoPago;
    abonoRequest.fields['cantidadpagar'] = abonoIngresado.toString();
    abonoRequest.fields['TotalPagado'] = abonoIngresado.toString();

    print('💰 ========================================');
    print('💰 CAMPOS MULTIPART:');
    print('💰 idpedido: ${idParaAbono}');
    print('💰 metodopago: $_metodoPago');
    print('💰 cantidadpagar: $abonoIngresado');
    print('💰 TotalPagado: $abonoIngresado');

    if (_comprobanteImagen != null && await _comprobanteImagen!.exists()) {
      var multipartFile = await http.MultipartFile.fromPath(
        'imagen',
        _comprobanteImagen!.path,
        filename: 'comprobante_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );

      abonoRequest.files.add(multipartFile);
      print('💰 Archivo adjunto: ${_comprobanteImagen!.path}');
    } else {
      throw Exception('Comprobante no existe o no se puede leer');
    }

    print('💰 ========================================');
    print('💰 ENVIANDO REQUEST.');

    var abonoStreamResponse = await abonoRequest.send().timeout(
      const Duration(seconds: 30),
      onTimeout: () => throw Exception('Timeout al crear abono con transferencia'),
    );

    var abonoResponse = await http.Response.fromStream(abonoStreamResponse);

    print('💰 ========================================');
    print('💰 RESPUESTA ABONO (TRANSFERENCIA)');
    print('💰 Status: ${abonoResponse.statusCode}');
    print('💰 ========================================');
    print('💰 Body:');
    print(abonoResponse.body);
    print('💰 ========================================');

    if (abonoResponse.statusCode == 200 || abonoResponse.statusCode == 201) {
      print('✅ ABONO CON TRANSFERENCIA CREADO EXITOSAMENTE');
      abonoExitoso = true;
    } else {
      print('⚠️ ERROR AL CREAR ABONO CON TRANSFERENCIA');
      mensajeErrorAbono = 'Status: ${abonoResponse.statusCode}, Body: ${abonoResponse.body}';
    }
  }

} catch (abonoError, abonoStackTrace) {
  print('❌ ========================================');
  print('❌ EXCEPCIÓN AL CREAR ABONO');
  print('❌ Error: $abonoError');
  print('❌ StackTrace: $abonoStackTrace');
  print('❌ ========================================');
  mensajeErrorAbono = abonoError.toString();
}

    // RESULTADO FINAL
    print('📊 ========================================');
    print('📊 RESUMEN FINAL');
    print('📊 Pedido creado: ✅');
    print('📊 Pedido ID: ${idPedido ?? "N/A"}');
    print('📊 Venta ID: ${idVenta ?? "N/A"}');
    print('📊 Abono exitoso: ${abonoExitoso ? "✅" : "❌"}');
    if (!abonoExitoso && mensajeErrorAbono.isNotEmpty) {
      print('📊 Error abono: $mensajeErrorAbono');
    }
    print('📊 ======================================== FIN');

    setState(() => _isLoading = false);
    cartService.clearCart();
    
    if (abonoExitoso) {
      _mostrarDialogoExito();
    } else {
      _mostrarDialogoExitoConAdvertencia(idPedido ?? idVenta);
    }

  } catch (e, stackTrace) {
    print('❌ ========================================');
    print('❌ ERROR CRÍTICO EN PROCESO COMPLETO');
    print('❌ Error: $e');
    print('❌ StackTrace: $stackTrace');
    print('❌ ========================================');
    
    setState(() => _isLoading = false);
    
    String errorMessage = 'Error al procesar pedido';
    if (e.toString().contains('SocketException') || e.toString().contains('Connection')) {
      errorMessage = 'Error de conexión. Verifica tu internet.';
    } else if (e.toString().contains('Timeout') || e.toString().contains('agotado')) {
      errorMessage = 'Tiempo de espera agotado. Intenta nuevamente.';
    } else if (e.toString().contains('FormatException')) {
      errorMessage = 'Error al procesar la respuesta del servidor.';
    } else {
      errorMessage = e.toString().replaceAll('Exception: ', '');
    }
    
    _mostrarMensaje(errorMessage, Colors.red);
  }
}

  //  FUNCIÓN AUXILIAR PARA EXTRAER IDs DE FORMA SEGURA
  int? _extraerIdSeguro(Map data, List<String> posiblesClaves) {
    for (String clave in posiblesClaves) {
      if (data.containsKey(clave)) {
        final valor = data[clave];
        if (valor is int) {
          return valor;
        } else if (valor is String) {
          return int.tryParse(valor);
        } else if (valor != null) {
          return int.tryParse(valor.toString());
        }
      }
    }
    return null;
  }

  void _mostrarDialogoExito() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.all(24),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: Colors.green[50],
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle, color: Colors.green, size: 60),
            ),
            const SizedBox(height: 20),
            const Text(
              '¡Pedido Exitoso!',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'Tu pedido ha sido registrado correctamente.',
              style: TextStyle(fontSize: 16, color: Colors.grey[700]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Recibirás una confirmación pronto.',
              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.of(context).pop();
                Navigator.of(context).pop();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.pink[400],
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Aceptar', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  void _mostrarDialogoExitoConAdvertencia(int? pedidoId) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.all(24),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: Colors.orange[50],
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 60),
            ),
            const SizedBox(height: 20),
            const Text(
              '¡Pedido Creado!',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              pedidoId != null 
                  ? 'Tu pedido #$pedidoId ha sido registrado correctamente.'
                  : 'Tu pedido ha sido registrado correctamente.',
              style: TextStyle(fontSize: 16, color: Colors.grey[700]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              '⚠️ Hubo un problema al registrar el abono. Contacta al administrador.',
              style: TextStyle(fontSize: 14, color: Colors.orange[700], fontWeight: FontWeight.w500),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.of(context).pop();
                Navigator.of(context).pop();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange[400],
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Aceptar', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  void _mostrarMensaje(String mensaje, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensaje),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  @override
  void dispose() {
    _observacionesController.dispose();
    _mensajeController.dispose();
    _abonoController.dispose();
    super.dispose();
  }// 🔥 CONTINUACIÓN - AGREGAR DESPUÉS DEL dispose() de la Parte 1

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Finalizar Compra', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.pink[400],
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      body: _isLoading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: Colors.pink[400]),
                  const SizedBox(height: 16),
                  const Text('Procesando pedido...', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 8),
                  Text(
                    'Por favor espera...',
                    style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                  ),
                ],
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildResumenPedido(),
                    const SizedBox(height: 20),
                    _buildSedeSelector(),
                    const SizedBox(height: 20),
                    _buildFechaSelector(),
                    const SizedBox(height: 20),
                    _buildMetodoPagoSelector(),
                    const SizedBox(height: 20),
                    _buildAbonoInput(),
                    if (_metodoPago == 'Transferencia') ...[
                      const SizedBox(height: 20),
                      _buildComprobanteUpload(),
                    ],
                    const SizedBox(height: 20),
                    _buildObservacionesInput(),
                    const SizedBox(height: 20),
                    _buildMensajeInput(),
                    const SizedBox(height: 30),
                    _buildConfirmButton(),
                    const SizedBox(height: 30),
                  ],
                ),
              ),
            ),
    );
  }

  // 🔥 WIDGETS UI

  Widget _buildResumenPedido() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.15),
            spreadRadius: 2,
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.receipt_long, color: Colors.pink, size: 24),
              SizedBox(width: 8),
              Text(
                'Resumen del Pedido',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Subtotal',
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
              Text(
                '\$${_formatPrice(_totalPedido)}',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              ),
            ],
          ),
          
          const SizedBox(height: 8),
          const Divider(),
          const SizedBox(height: 8),
          
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Total',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              Text(
                '\$${_formatPrice(_totalPedido)}',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.pink[400],
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 12),
          const Divider(),
          const SizedBox(height: 12),
          
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.pink[50],
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '💡 Información importante:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                SizedBox(height: 4),
                Text(
                  '• Mínimo 10 productos por pedido\n• Entrega en 15-30 días\n• Abono mínimo 50%',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSedeSelector() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.grey.withOpacity(0.15), spreadRadius: 2, blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.store, color: Colors.pink[400], size: 24),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Sede para recoger',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              if (_sedeSeleccionada == null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.orange[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Requerido',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.orange,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (_isLoadingSedes)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: CircularProgressIndicator(color: Colors.pink[400]),
              ),
            )
          else if (_sedes.isEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orange[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange[200]!),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.orange[700]),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'No hay sedes disponibles',
                      style: TextStyle(color: Colors.orange, fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            )
          else
            ..._sedes.map((sede) => _buildSedeOption(sede)),
        ],
      ),
    );
  }

  Widget _buildSedeOption(dynamic sede) {
    final dynamic sedeIdDynamic = sede['idsede'] ?? sede['idSede'] ?? sede['id'] ?? sede['IdSede'];
    
    if (sedeIdDynamic == null) {
      return const SizedBox.shrink();
    }
    
    final int sedeIdFinal = sedeIdDynamic is int 
        ? sedeIdDynamic 
        : int.tryParse(sedeIdDynamic.toString()) ?? 0;
    
    if (sedeIdFinal == 0) {
      return const SizedBox.shrink();
    }
    
    final String nombreSede = sede['nombre'] ?? sede['nombreSede'] ?? 'Sin nombre';
    final String direccion = sede['direccion'] ?? 'Sin dirección';
    final String telefono = sede['telefono'] ?? '';
    final bool isSelected = _sedeSeleccionada == sedeIdFinal;
    
    return GestureDetector(
      onTap: () {
        setState(() {
          _sedeSeleccionada = sedeIdFinal;
        });
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? Colors.pink[50] : Colors.grey[50],
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
            color: isSelected ? Colors.pink[400]! : Colors.grey[300]!,
            width: 2,
          ),
        ),
        child: Row(
          children: [
            Radio<int>(
              value: sedeIdFinal,
              groupValue: _sedeSeleccionada,
              onChanged: (value) {
                setState(() {
                  _sedeSeleccionada = value;
                });
              },
              activeColor: Colors.pink[400],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    nombreSede,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: isSelected ? Colors.pink[700] : Colors.black,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(direccion, style: TextStyle(fontSize: 14, color: Colors.grey[600])),
                  if (telefono.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text('Tel: $telefono', style: TextStyle(fontSize: 13, color: Colors.grey[500])),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFechaSelector() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.grey.withOpacity(0.15), spreadRadius: 2, blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.calendar_today, color: Colors.pink[400], size: 24),
              const SizedBox(width: 8),
              const Text('Fecha de entrega', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 16),
          InkWell(
            onTap: _seleccionarFecha,
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.pink[50]!, Colors.pink[100]!.withOpacity(0.3)],
                ),
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: Colors.pink[200]!),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.pink[400],
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.event, color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _fechaEntrega == null
                              ? 'Seleccionar fecha'
                              : '${_fechaEntrega!.day.toString().padLeft(2, '0')}/${_fechaEntrega!.month.toString().padLeft(2, '0')}/${_fechaEntrega!.year}',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: _fechaEntrega == null ? Colors.grey[600] : Colors.black,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Mínimo 15 días, máximo 30 días',
                          style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.arrow_forward_ios, size: 18, color: Colors.pink[400]),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetodoPagoSelector() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.grey.withOpacity(0.15), spreadRadius: 2, blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.payment, color: Colors.pink[400], size: 24),
              const SizedBox(width: 8),
              const Text('Método de pago', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 16),
          _buildMetodoPagoOption('Efectivo', Icons.money),
          const SizedBox(height: 10),
          _buildMetodoPagoOption('Transferencia', Icons.account_balance),
        ],
      ),
    );
  }

  Widget _buildMetodoPagoOption(String metodo, IconData icon) {
    final bool isSelected = _metodoPago == metodo;
    return GestureDetector(
      onTap: () {
        setState(() {
          _metodoPago = metodo;
          // Limpiar comprobante si cambio a efectivo
          if (metodo == 'Efectivo') {
            _comprobanteImagen = null;
          }
        });
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? Colors.pink[50] : Colors.grey[50],
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: isSelected ? Colors.pink[400]! : Colors.grey[300]!, width: 2),
        ),
        child: Row(
          children: [
            Radio<String>(
              value: metodo,
              groupValue: _metodoPago,
              onChanged: (value) {
                setState(() {
                  _metodoPago = value!;
                  if (value == 'Efectivo') {
                    _comprobanteImagen = null;
                  }
                });
              },
              activeColor: Colors.pink[400],
            ),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isSelected ? Colors.pink[100] : Colors.grey[200],
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: isSelected ? Colors.pink[700] : Colors.grey[600], size: 24),
            ),
            const SizedBox(width: 12),
            Text(
              metodo,
              style: TextStyle(
                fontSize: 16,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? Colors.pink[700] : Colors.black,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAbonoInput() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.grey.withOpacity(0.15), spreadRadius: 2, blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.attach_money, color: Colors.pink[400], size: 24),
              const SizedBox(width: 8),
              const Text('Abono (mínimo 50%)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _abonoController,
            keyboardType: TextInputType.number,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            decoration: InputDecoration(
              prefixIcon: Icon(Icons.monetization_on, color: Colors.pink[400]),
              hintText: 'Ingresa el monto del abono',
              filled: true,
              fillColor: Colors.pink[50],
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(15),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(15),
                borderSide: BorderSide(color: Colors.pink[200]!, width: 2),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(15),
                borderSide: BorderSide(color: Colors.pink[400]!, width: 2),
              ),
              errorMaxLines: 3,
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Ingresa el monto del abono';
              }
              
              String valorLimpio = value.replaceAll('.', '');
              final double? monto = double.tryParse(valorLimpio);
              
              if (monto == null) {
                return 'Ingresa un monto válido (solo números)';
              }
              
              if (monto < _totalPedido * 0.5) {
                return 'El abono debe ser mínimo el 50% (\$${_formatPrice(_totalPedido * 0.5)})';
              }
              
              if (monto > _totalPedido) {
                return 'El abono no puede ser mayor al total del pedido';
              }
              
              return null;
            },
            onChanged: (value) {
              if (value.isNotEmpty) {
                String cleanValue = value.replaceAll('.', '');
                if (cleanValue.isNotEmpty) {
                  double? numericValue = double.tryParse(cleanValue);
                  if (numericValue != null) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      _abonoController.value = _abonoController.value.copyWith(
                        text: _formatNumberForDisplay(numericValue),
                        selection: TextSelection.collapsed(offset: _formatNumberForDisplay(numericValue).length),
                      );
                    });
                  }
                }
              }
            },
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.green[50],
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.green[200]!),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.green[700], size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'El 50% restante se paga al recoger el pedido\nAbono mínimo: \$${_formatPrice(_totalPedido * 0.5)}',
                    style: TextStyle(fontSize: 13, color: Colors.green[900], fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 🔥 WIDGET PARA SUBIDA DE COMPROBANTE CON VISTA PREVIA
  Widget _buildComprobanteUpload() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.grey.withOpacity(0.15), spreadRadius: 2, blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.upload_file, color: Colors.pink[400], size: 24),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Comprobante de transferencia',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.orange[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'Requerido',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.orange,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          // 🔥 VISTA PREVIA EN TIEMPO REAL
          if (_comprobanteImagen != null) ...[
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: Colors.pink[200]!, width: 2),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(13),
                child: Stack(
                  children: [
                    Image.file(
                      _comprobanteImagen!, 
                      height: 250, 
                      width: double.infinity, 
                      fit: BoxFit.cover
                    ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.6),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: IconButton(
                          icon: const Icon(Icons.close, color: Colors.white, size: 20),
                          onPressed: () {
                            setState(() {
                              _comprobanteImagen = null;
                            });
                          },
                          padding: const EdgeInsets.all(8),
                          constraints: const BoxConstraints(),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.9),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.check_circle, color: Colors.white, size: 16),
                            SizedBox(width: 6),
                            Text(
                              'Comprobante cargado',
                              style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          
          // BOTÓN PARA SUBIR/CAMBIAR COMPROBANTE
          ElevatedButton.icon(
            onPressed: _seleccionarComprobante,
            icon: Icon(
              _comprobanteImagen == null ? Icons.camera_alt : Icons.change_circle, 
              size: 24
            ),
            label: Text(
              _comprobanteImagen == null ? 'Subir Comprobante' : 'Cambiar Comprobante',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.pink[400],
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 55),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              elevation: 3,
            ),
          ),
          
          // INFORMACIÓN ADICIONAL
          if (_comprobanteImagen == null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.blue[200]!),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, color: Colors.blue[700], size: 20),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Sube una imagen clara de tu comprobante de transferencia.',
                      style: TextStyle(fontSize: 13, color: Colors.blue),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildObservacionesInput() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.grey.withOpacity(0.15), spreadRadius: 2, blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.note_alt, color: Colors.pink[400], size: 24),
              const SizedBox(width: 8),
              const Text('Observaciones', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(width: 8),
              Text('(opcional)', style: TextStyle(fontSize: 14, color: Colors.grey[600])),
            ],
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _observacionesController,
            maxLines: 3,
            maxLength: 200,
            decoration: InputDecoration(
              hintText: 'Detalles adicionales sobre el pedido...',
              filled: true,
              fillColor: Colors.grey[50],
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(15),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(15),
                borderSide: BorderSide(color: Colors.grey[300]!, width: 2),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(15),
                borderSide: BorderSide(color: Colors.pink[400]!, width: 2),
              ),
              counterStyle: TextStyle(color: Colors.grey[600], fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMensajeInput() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.grey.withOpacity(0.15), spreadRadius: 2, blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.card_giftcard, color: Colors.pink[400], size: 24),
              const SizedBox(width: 8),
              const Text('Mensaje personalizado', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(width: 8),
              Text('(opcional)', style: TextStyle(fontSize: 14, color: Colors.grey[600])),
            ],
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _mensajeController,
            maxLines: 2,
            maxLength: 100,
            decoration: InputDecoration(
              hintText: 'Mensaje que aparecerá en el producto...',
              filled: true,
              fillColor: Colors.grey[50],
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(15),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(15),
                borderSide: BorderSide(color: Colors.grey[300]!, width: 2),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(15),
                borderSide: BorderSide(color: Colors.pink[400]!, width: 2),
              ),
              counterStyle: TextStyle(color: Colors.grey[600], fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConfirmButton() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.pink.withOpacity(0.4),
            spreadRadius: 2,
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: _procesarPedido,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.pink[400],
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 60),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          elevation: 0,
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle, size: 28),
            SizedBox(width: 12),
            Text('Confirmar Pedido', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}

