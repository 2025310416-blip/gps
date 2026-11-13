import hashlib              #<--Encriptar las contraseñas
import requests             #<-- Peticiones HTTP hacia APIs externas
from fastapi import FastAPI, HTTPException, Depends #<--Importa el framework, manejo de errores HTTP
from fastapi.middleware.cors import CORSMiddleware #<--permitir conexiones desde dominios/apps externas
from pydantic import BaseModel  #<--Clase base para validar la estructura y tipos de datos JSON recibidos.
from sqlalchemy import create_engine, Column, Integer, String, Double, Text, TIMESTAMP, ForeignKey, text
from sqlalchemy.orm import sessionmaker, declarative_base, Session

# --------------- Configuración de conexión a MySQL ------------------
DATABASE_URL = "mysql+pymysql://root:@localhost:3306/asistencia_gps"

engine = create_engine(DATABASE_URL)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()
#----------------------------------------------------------------------
app = FastAPI()

# Habilitar CORS para peticiones desde Flutter
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

#====================================================================
# --- MODELOS SQLALCHEMY ---
#====================================================================

class User(Base):
    __tablename__ = "users"
    id = Column(Integer, primary_key=True, index=True)
    username = Column(String(50), unique=True, nullable=False)
    password = Column(String(32), nullable=False)

class Attendance(Base):
    __tablename__ = "attendance"
    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    latitude = Column(Double, nullable=False)
    longitude = Column(Double, nullable=False)
    address = Column(Text, nullable=False)
    created_at = Column(TIMESTAMP, server_default=text("CURRENT_TIMESTAMP"))

Base.metadata.create_all(bind=engine)

#====================================================================
# --- MODELOS PYDANTIC ---
#====================================================================
class RegisterModel(BaseModel):
    username: str
    password: str

class LoginModel(BaseModel):
    username: str
    password: str

class AttendanceModel(BaseModel):
    user_id: int
    latitude: float
    longitude: float

# --- UTILIDADES ---
def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

def md5_hash(password: str) -> str:#<--Transforma la contraseña de un texto plano a un HASH D5 de 32 caracteres para no GUARDARLA VISIBLE
    return hashlib.md5(password.encode()).hexdigest()

def get_address_from_nominatim(lat: float, lon: float) -> str:#<--Devuelve la latitud y longitud a la API y devuleve la direccion textual (calle, colonia y ciudad)
    url = f"https://nominatim.openstreetmap.org/reverse?format=json&lat={lat}&lon={lon}"
    headers = {"User-Agent": "FlutterAttendanceApp/1.0"}
    try:
        response = requests.get(url, headers=headers, timeout=10)
        if response.status_code == 200:
            data = response.json()
            return data.get("display_name", "Dirección no encontrada")
    except Exception:
        pass
    return "Error al consultar la dirección"

#====================================================================
# --- ENDPOINTS ---
#====================================================================

@app.post("/register/")
def register(user: RegisterModel, db: Session = Depends(get_db)):
    existing = db.query(User).filter(User.username == user.username).first()
    if existing:#<---si existe devuelve un erro 400 x_x
        raise HTTPException(status_code=400, detail="El usuario ya existe")

    #Crea un usuario encriptando su contraseña
    new_user = User(username=user.username, password=md5_hash(user.password))
    db.add(new_user)
    db.commit() #<--Lo guarda en la base de datos 
    db.refresh(new_user) #<--Envia un mensaje
    return {"message": "Usuario registrado exitosamente", "user_id": new_user.id}

@app.post("/login/")
def login(user: LoginModel, db: Session = Depends(get_db)):
    hashed_pw = md5_hash(user.password)#<--- Compara la contraseña (Convertirla en MD5)
    db_user = db.query(User).filter(User.username == user.username, User.password ==hashed_pw).first()

    #No coincide 
    if not db_user:
        raise HTTPException(status_code=401, detail="Credenciales incorrectas")

    #Si coincide :)
    return {"message": "Login exitoso", "user_id":db_user.id, "username": db_user.username}


#Endpoint Registrar asistencia
@app.post("/attendance/")
def register_attendance(data: AttendanceModel, db: Session = Depends(get_db)):
    # Buscar al usuario en la base de datos
    user = db.query(User).filter(User.id == data.user_id).first()

    # Verificar si el usuario existe
    if not user:
        raise HTTPException(status_code=404,detail="Usuario no registrado")

    # Obtener la dirección mediante las coordenadas GPS
    address = get_address_from_nominatim(data.latitude,data.longitude)

    # Crear el registro de asistencia
    new_record = Attendance(
        user_id=data.user_id,
        latitude=data.latitude,
        longitude=data.longitude,
        address=address
    )

    # Guardar el registro en MySQL
    db.add(new_record)
    db.commit()
    db.refresh(new_record)

    return {
        "message": "Asistencia registrada",
        "address": address,
        "latitude": data.latitude,
        "longitude": data.longitude
    }

# Endpoint GET: Mostrar el historial
@app.get("/attendance/")
#Recibe como parámetros el usuario y abre la conexion activa hacia MySQL PARA LA CONSULTA
def get_attendance_history(user_id: int, db: Session = Depends(get_db)): #<--
    
    #1.Inicia la consulta y guarda el resultado en la variable records     
    records = ( 
        db.query(Attendance) #<--consulte con la tabla attendance
        .filter(Attendance.user_id == user_id) #<--Filtra las filas para obtener las asistencias del usuario
        .order_by(Attendance.created_at.desc())#<--ordena los regsitros por fecha de forma ascendente
        .all()
    )

    #Retornara la lista de objetos
    return [
        {
            "address": r.address, #Extrae la direccion guardada en el regsitro
            "latitude": r.latitude, #Extrae la latitud guardada en r
            "longitude": r.longitude,
            "created_at": str(r.created_at), #Convierte la fecha y hora en texto "str"
        }
        for r in records # Recorre cada uno de los registros obtenidos
    ]
