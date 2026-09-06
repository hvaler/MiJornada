# Mocking Avanzado con Moq

> Skill: testing-patterns
> Versión: 2.8.0

---

## Descripción

Patrones avanzados de mocking para tests unitarios utilizando Moq,
incluyendo setup condicional, callbacks, secuencias y verificaciones complejas.

---

## Setup Condicional

### Por Parámetros

```csharp
// Setup diferente según el valor del parámetro
_repositoryMock
    .Setup(r => r.GetByIdAsync(1, It.IsAny<CancellationToken>()))
    .ReturnsAsync(new Scholarship { Id = 1, Name = "Scholarship 1" });

_repositoryMock
    .Setup(r => r.GetByIdAsync(2, It.IsAny<CancellationToken>()))
    .ReturnsAsync(new Scholarship { Id = 2, Name = "Scholarship 2" });

_repositoryMock
    .Setup(r => r.GetByIdAsync(It.Is<int>(id => id > 100), It.IsAny<CancellationToken>()))
    .ReturnsAsync((Scholarship?)null);
```

### Con Predicados

```csharp
// Setup con condición compleja
_repositoryMock
    .Setup(r => r.GetByCodeAsync(
        It.Is<string>(c => c.StartsWith("BECA-")),
        It.IsAny<CancellationToken>()))
    .ReturnsAsync(new Scholarship { Code = "BECA-001" });

// Coincidencia por regex
_repositoryMock
    .Setup(r => r.SearchAsync(
        It.IsRegex(@"^[A-Z]{4}-\d{3}$"),
        It.IsAny<CancellationToken>()))
    .ReturnsAsync(new List<Scholarship>());
```

---

## Callbacks

### Capturar Argumentos

```csharp
Scholarship? savedScholarship = null;

_repositoryMock
    .Setup(r => r.AddAsync(It.IsAny<Scholarship>(), It.IsAny<CancellationToken>()))
    .Callback<Scholarship, CancellationToken>((scholarship, _) =>
    {
        savedScholarship = scholarship;
        scholarship.Id = 1; // Simular asignación de ID
    })
    .ReturnsAsync((Scholarship b, CancellationToken _) => b);

// Después del test
await _sut.CreateAsync(request);
savedScholarship.Should().NotBeNull();
savedScholarship!.Name.Should().Be("New Scholarship");
```

### Ejecutar Lógica

```csharp
var contador = 0;

_serviceMock
    .Setup(s => s.ProcessAsync(It.IsAny<int>(), It.IsAny<CancellationToken>()))
    .Callback(() => contador++)
    .Returns(Task.CompletedTask);

// Verificar número de llamadas
await _sut.ProcessAllAsync();
contador.Should().Be(5);
```

---

## Secuencias

### Retornos Diferentes por Llamada

```csharp
// Primera llamada retorna null, segunda retorna la entidad
_repositoryMock
    .SetupSequence(r => r.GetByIdAsync(1, It.IsAny<CancellationToken>()))
    .ReturnsAsync((Scholarship?)null)      // Primera llamada
    .ReturnsAsync(new Scholarship { Id = 1 }); // Segunda llamada
```

### Simulando Reintentos

```csharp
// Simular fallo y luego éxito
_externalServiceMock
    .SetupSequence(s => s.CallApiAsync())
    .ThrowsAsync(new HttpRequestException("Timeout"))  // 1er intento falla
    .ThrowsAsync(new HttpRequestException("Timeout"))  // 2do intento falla
    .ReturnsAsync(new ApiResponse { Success = true }); // 3er intento OK
```

---

## Métodos Async

### Task Completado

```csharp
_serviceMock
    .Setup(s => s.ProcessAsync(It.IsAny<int>()))
    .Returns(Task.CompletedTask);
```

### Con Delay (para tests de timeout)

```csharp
_serviceMock
    .Setup(s => s.SlowOperationAsync())
    .Returns(async () =>
    {
        await Task.Delay(5000); // Simula operación lenta
        return new Result();
    });
```

### Cancelación

```csharp
_serviceMock
    .Setup(s => s.LongRunningAsync(It.IsAny<CancellationToken>()))
    .Returns<CancellationToken>(async ct =>
    {
        await Task.Delay(1000, ct); // Respeta cancelación
        return new Result();
    });
```

---

## Verificaciones Avanzadas

### Verificar Orden de Llamadas

```csharp
var sequence = new MockSequence();

_repositoryMock.InSequence(sequence)
    .Setup(r => r.GetByIdAsync(1, It.IsAny<CancellationToken>()));

_repositoryMock.InSequence(sequence)
    .Setup(r => r.UpdateAsync(It.IsAny<Scholarship>(), It.IsAny<CancellationToken>()));

// Si se llaman en orden diferente, el test falla
```

### Verificar Argumentos Complejos

```csharp
_repositoryMock.Verify(
    r => r.AddAsync(
        It.Is<Scholarship>(b =>
            b.Name == "Test" &&
            b.Amount > 0 &&
            b.Status == ScholarshipStatus.Draft),
        It.IsAny<CancellationToken>()),
    Times.Once);
```

### Verificar Nunca Llamado

```csharp
_emailServiceMock.Verify(
    s => s.SendAsync(It.IsAny<Email>(), It.IsAny<CancellationToken>()),
    Times.Never,
    "No debería enviar email cuando la scholarship está en borrador");
```

### Capturar y Verificar Después

```csharp
// Capturar todas las llamadas
var invocaciones = new List<Scholarship>();

_repositoryMock
    .Setup(r => r.UpdateAsync(It.IsAny<Scholarship>(), It.IsAny<CancellationToken>()))
    .Callback<Scholarship, CancellationToken>((b, _) => invocaciones.Add(b))
    .Returns(Task.CompletedTask);

// Ejecutar
await _sut.UpdateVariasAsync(ids);

// Verificar
invocaciones.Should().HaveCount(3);
invocaciones.Should().OnlyContain(b => b.Status == ScholarshipStatus.Actualizada);
```

---

## Mock de Propiedades

```csharp
// Propiedad get/set
_configMock
    .SetupProperty(c => c.Setting, "valor-inicial");

// Verificar que se modificó
_configMock.Object.Setting = "nuevo-valor";
_configMock.VerifySet(c => c.Setting = "nuevo-valor");

// Propiedad solo lectura
_serviceMock
    .SetupGet(s => s.IsConnected)
    .Returns(true);
```

---

## Mock de Eventos

```csharp
// Configurar evento
var eventRaised = false;

_serviceMock
    .Setup(s => s.ProcessAsync())
    .Callback(() =>
    {
        _serviceMock.Raise(s => s.Completed += null, EventArgs.Empty);
    });

// Suscribirse
_serviceMock.Object.Completed += (_, _) => eventRaised = true;

// Act
await _sut.ExecuteAsync();

// Assert
eventRaised.Should().BeTrue();
```

---

## Mock Strict vs Loose

```csharp
// Strict - Falla si se llama algo no configurado
var strictMock = new Mock<IRepository>(MockBehavior.Strict);
strictMock.Setup(r => r.GetByIdAsync(1, It.IsAny<CancellationToken>()))
    .ReturnsAsync(new Scholarship());

// Loose (default) - Retorna default para no configurados
var looseMock = new Mock<IRepository>(MockBehavior.Loose);
// GetByIdAsync(999) retornará null sin configurar

// Recomendación: Usar Strict para tests críticos
```

---

## Mock de Clases Concretas

```csharp
// Requiere métodos virtual
public class EmailService
{
    public virtual Task SendAsync(string to, string subject) { ... }
}

var mock = new Mock<EmailService>();
mock.Setup(s => s.SendAsync(It.IsAny<string>(), It.IsAny<string>()))
    .Returns(Task.CompletedTask);

// Llamar método real para algunos casos
mock.Setup(s => s.ValidateEmail(It.IsAny<string>()))
    .CallBase(); // Usa implementación real
```

---

## Helpers de Mocking

```csharp
public static class MockExtensions
{
    public static void SetupGetById<T>(
        this Mock<IRepository<T>> mock,
        int id,
        T? entity) where T : Entity
    {
        mock.Setup(r => r.GetByIdAsync(id, It.IsAny<CancellationToken>()))
            .ReturnsAsync(entity);
    }

    public static void SetupAddReturnsWithId<T>(
        this Mock<IRepository<T>> mock,
        int newId) where T : Entity
    {
        mock.Setup(r => r.AddAsync(It.IsAny<T>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync((T entity, CancellationToken _) =>
            {
                typeof(T).GetProperty("Id")!.SetValue(entity, newId);
                return entity;
            });
    }
}

// Uso
_repositoryMock.SetupGetById(1, new Scholarship { Id = 1 });
_repositoryMock.SetupAddReturnsWithId(99);
```

---

## Anti-Patterns a Evitar

| Anti-Pattern | Problema | Solución |
|--------------|----------|----------|
| Over-mocking | Tests frágiles | Mock solo dependencias directas |
| Mock de DTOs | Innecesario | Usar instancias reales |
| Setup genérico It.IsAny | Tests poco específicos | Ser específico cuando importa |
| Verificar implementación | Tests acoplados | Verificar comportamiento |

---

*Pattern v1.0 - testing-patterns skill*
