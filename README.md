# Lab DE — Fase 0: el terreno

Laboratorio local de data engineering sobre un dominio de nómina LATAM **sintético**.
Nada de este repo toca datos reales de ningún cliente.

## Requisitos previos

1. **Docker Desktop** para Windows (con backend WSL2). Requiere virtualización habilitada en BIOS.
2. **Git** y una cuenta de GitHub.
3. **SSMS** o **Azure Data Studio** (ya lo tienes).
4. Python 3.12 y VS Code — se usan hasta la fase 2, pero puedes instalarlos desde ahora.

## Pasos

### 1. Prepara el entorno

```powershell
cd C:\dev\lab-de
copy .env.example .env
```

Abre `.env` y cambia la clave. Requisitos de SQL Server: mínimo 8 caracteres,
con mayúscula, minúscula, número y símbolo. Si no cumple, el contenedor arranca
y se apaga solo a los segundos.

### 2. Levanta el contenedor

```powershell
docker compose up -d
docker compose ps
docker compose logs -f sqlserver
```

En los logs debe aparecer `SQL Server is now ready for client connections`.
`Ctrl+C` solo cierra los logs, no el contenedor.

### 3. Conéctate

Desde SSMS:

- Servidor: `localhost,1434`
- Autenticación: SQL Server Authentication
- Usuario: `sa`
- Contraseña: la de tu `.env`
- Marca **Trust server certificate**

### 4. Verifica y crea la base

```sql
SELECT @@VERSION;

CREATE DATABASE LabNomina;
GO

USE LabNomina;
SELECT DB_NAME() AS BaseActual, SUSER_NAME() AS Usuario;
```

### 5. Versiona el repo

```powershell
git init
git add .
git commit -m "Fase 0: contenedor de SQL Server para el laboratorio"
```

Confirma que `.env` NO aparece en `git status`. Si aparece, revisa el `.gitignore`.

## Comandos del día a día

| Acción | Comando |
|---|---|
| Levantar | `docker compose up -d` |
| Apagar (conserva datos) | `docker compose stop` |
| Apagar y borrar contenedor | `docker compose down` |
| Borrar TODO, datos incluidos | `docker compose down -v` |
| Entrar al contenedor | `docker exec -it lab_sqlserver bash` |

## Criterio de éxito de la fase 0

- [ ] `docker compose ps` muestra el contenedor en estado `running`
- [ ] Conectas desde SSMS a `localhost,1434`
- [ ] `SELECT @@VERSION` responde SQL Server 2022
- [ ] Existe la base `LabNomina`
- [ ] Apagas y vuelves a levantar el contenedor, y `LabNomina` sigue ahí
