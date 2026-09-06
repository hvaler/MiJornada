# Patrón Builder para Tests

> Skill: testing-patterns
> Versión: 2.8.0

---

## Descripción

El patrón Builder permite construir objetos de test de forma fluida y expresiva,
evitando constructores con muchos parámetros y haciendo los tests más legibles.

---

## Builder Genérico

```csharp
public abstract class Builder<T, TBuilder> where TBuilder : Builder<T, TBuilder>
{
    protected abstract T Build();

    public static implicit operator T(Builder<T, TBuilder> builder) => builder.Build();
}
```

---

## Builder para Entidad Scholarship

```csharp
public class ScholarshipBuilder : Builder<Scholarship, ScholarshipBuilder>
{
    private int _id = 1;
    private string _codigo = "BECA-001";
    private string _nombre = "Scholarship de Prueba";
    private string? _descripcion;
    private decimal _importe = 5000m;
    private ScholarshipStatus _estado = ScholarshipStatus.Draft;
    private DateTime _startDate = DateTime.Today;
    private DateTime _endDate = DateTime.Today.AddMonths(6);
    private List<ScholarshipApplication> _applications = [];

    public ScholarshipBuilder ConId(int id)
    {
        _id = id;
        return this;
    }

    public ScholarshipBuilder ConCode(string code)
    {
        _codigo = code;
        return this;
    }

    public ScholarshipBuilder ConNombre(string name)
    {
        _nombre = name;
        return this;
    }

    public ScholarshipBuilder ConDescription(string descripcion)
    {
        _descripcion = descripcion;
        return this;
    }

    public ScholarshipBuilder ConAmount(decimal amount)
    {
        _importe = amount;
        return this;
    }

    public ScholarshipBuilder ConEstado(ScholarshipStatus status)
    {
        _estado = status;
        return this;
    }

    public ScholarshipBuilder Published()
    {
        _estado = ScholarshipStatus.Published;
        return this;
    }

    public ScholarshipBuilder Closed()
    {
        _estado = ScholarshipStatus.Closed;
        return this;
    }

    public ScholarshipBuilder ConPeriod(DateTime start, DateTime end)
    {
        _startDate = start;
        _endDate = end;
        return this;
    }

    public ScholarshipBuilder ConScholarshipApplication(ScholarshipApplication application)
    {
        _applications.Add(application);
        return this;
    }

    public ScholarshipBuilder ConApplications(int amount)
    {
        for (int i = 0; i < amount; i++)
        {
            _applications.Add(new ScholarshipApplicationBuilder()
                .ConScholarshipId(_id)
                .ConStudentId(i + 1)
                .Build());
        }
        return this;
    }

    protected override Scholarship Build()
    {
        var scholarship = Scholarship.Create(_codigo, _nombre, _importe,
            new Period(_startDate, _endDate));

        // Usar reflection para setear Id y otros campos privados en tests
        SetPrivateProperty(scholarship, nameof(Scholarship.Id), _id);
        SetPrivateProperty(scholarship, nameof(Scholarship.Description), _descripcion);
        SetPrivateProperty(scholarship, nameof(Scholarship.Status), _estado);

        foreach (var application in _applications)
        {
            // Agregar a colección privada
            var field = typeof(Scholarship).GetField("_applications",
                BindingFlags.NonPublic | BindingFlags.Instance);
            var list = (List<ScholarshipApplication>)field!.GetValue(scholarship)!;
            list.Add(application);
        }

        return scholarship;
    }

    private static void SetPrivateProperty<TValue>(object obj, string propertyName, TValue value)
    {
        var property = obj.GetType().GetProperty(propertyName,
            BindingFlags.Public | BindingFlags.Instance);

        if (property?.CanWrite == true)
        {
            property.SetValue(obj, value);
        }
        else
        {
            // Intentar con backing field
            var field = obj.GetType().GetField($"<{propertyName}>k__BackingField",
                BindingFlags.NonPublic | BindingFlags.Instance);
            field?.SetValue(obj, value);
        }
    }
}
```

---

## Builder para DTOs

```csharp
public class ScholarshipDtoBuilder
{
    private int _id = 1;
    private string _codigo = "BECA-001";
    private string _nombre = "Scholarship de Prueba";
    private decimal _importe = 5000m;
    private string _estado = "Draft";
    private DateTime _startDate = DateTime.Today;
    private DateTime _endDate = DateTime.Today.AddMonths(6);

    public ScholarshipDtoBuilder ConId(int id)
    {
        _id = id;
        return this;
    }

    public ScholarshipDtoBuilder ConNombre(string name)
    {
        _nombre = name;
        return this;
    }

    public ScholarshipDtoBuilder ConAmount(decimal amount)
    {
        _importe = amount;
        return this;
    }

    public ScholarshipDtoBuilder Published()
    {
        _estado = "Published";
        return this;
    }

    public ScholarshipDto Build() => new()
    {
        Id = _id,
        Code = _codigo,
        Name = _nombre,
        Amount = _importe,
        Status = _estado,
        StartDate = _startDate,
        EndDate = _endDate
    };

    public static implicit operator ScholarshipDto(ScholarshipDtoBuilder builder) => builder.Build();
}
```

---

## Builder para Requests

```csharp
public class CreateScholarshipRequestBuilder
{
    private string _codigo = "BECA-001";
    private string _nombre = "New Scholarship";
    private string? _descripcion;
    private decimal _importe = 5000m;
    private DateTime _startDate = DateTime.Today.AddDays(1);
    private DateTime _endDate = DateTime.Today.AddMonths(6);

    public CreateScholarshipRequestBuilder ConCode(string code)
    {
        _codigo = code;
        return this;
    }

    public CreateScholarshipRequestBuilder ConNombre(string name)
    {
        _nombre = name;
        return this;
    }

    public CreateScholarshipRequestBuilder SinNombre()
    {
        _nombre = string.Empty;
        return this;
    }

    public CreateScholarshipRequestBuilder ConAmount(decimal amount)
    {
        _importe = amount;
        return this;
    }

    public CreateScholarshipRequestBuilder ConAmountInvalido()
    {
        _importe = -1000m;
        return this;
    }

    public CreateScholarshipRequestBuilder ConFechasInvalidas()
    {
        _startDate = DateTime.Today.AddMonths(6);
        _endDate = DateTime.Today; // Fin antes que start
        return this;
    }

    public CreateScholarshipCommand Build() => new()
    {
        Code = _codigo,
        Name = _nombre,
        Description = _descripcion,
        Amount = _importe,
        StartDate = _startDate,
        EndDate = _endDate
    };
}
```

---

## Uso en Tests

```csharp
public class ScholarshipServiceTests
{
    [Fact]
    public async Task GetById_ScholarshipExists_ReturnsScholarshipDto()
    {
        // Arrange - Uso fluido del builder
        var scholarship = new ScholarshipBuilder()
            .ConId(1)
            .ConNombre("Scholarship Excelencia")
            .ConAmount(10000m)
            .Published()
            .Build();

        _repositoryMock
            .Setup(r => r.GetByIdAsync(1, It.IsAny<CancellationToken>()))
            .ReturnsAsync(scholarship);

        // Act
        var result = await _sut.GetByIdAsync(1);

        // Assert
        result.Should().NotBeNull();
        result!.Name.Should().Be("Scholarship Excelencia");
    }

    [Fact]
    public async Task Create_ValidData_CreatesYReturnsScholarship()
    {
        // Arrange
        var request = new CreateScholarshipRequestBuilder()
            .ConNombre("New Scholarship")
            .ConAmount(5000m)
            .Build();

        // Act & Assert
        // ...
    }

    [Fact]
    public async Task Delete_ScholarshipWithApplications_ThrowsExcepcion()
    {
        // Arrange
        var scholarship = new ScholarshipBuilder()
            .ConId(1)
            .Published()
            .ConApplications(5) // 5 applications generadas
            .Build();

        // Act & Assert
        // ...
    }
}
```

---

## Factoría de Builders

```csharp
public static class TestDataFactory
{
    public static ScholarshipBuilder Scholarship() => new();
    public static ScholarshipApplicationBuilder ScholarshipApplication() => new();
    public static StudentBuilder Student() => new();
    public static CreateScholarshipRequestBuilder CreateScholarshipRequest() => new();

    // Builders predefinidos para escenarios comunes
    public static Scholarship ScholarshipPublishedValida() => new ScholarshipBuilder()
        .Published()
        .ConPeriod(DateTime.Today, DateTime.Today.AddMonths(6))
        .Build();

    public static Scholarship ScholarshipClosedConApplications() => new ScholarshipBuilder()
        .Closed()
        .ConApplications(10)
        .Build();
}

// Uso
var scholarship = TestDataFactory.ScholarshipPublishedValida();
var request = TestDataFactory.CreateScholarshipRequest().ConNombre("Mi Scholarship").Build();
```

---

## Ventajas del Patrón Builder

| Ventaja | Descripción |
|---------|-------------|
| **Legibilidad** | Tests autodocumentados |
| **Mantenibilidad** | Cambios centralizados |
| **Flexibilidad** | Fácil crear variaciones |
| **Reutilización** | Builders compartidos |
| **Defaults sensatos** | Valores por defecto válidos |

---

*Pattern v1.0 - testing-patterns skill*
