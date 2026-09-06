# Performance Testing

> Skill: testing-patterns | Version: 3.1.0

BenchmarkDotNet para microbenchmarks y NBomber/k6 para load testing.

---

## BenchmarkDotNet

```csharp
[MemoryDiagnoser]
[SimpleJob(RuntimeMoniker.Net100)]
public class SerializationBenchmarks
{
    private readonly ScholarshipDto _dto = new() { Id = 1, Name = "Test" };

    [Benchmark(Baseline = true)]
    public string SystemTextJson()
        => JsonSerializer.Serialize(_dto);

    [Benchmark]
    public string SystemTextJsonSourceGen()
        => JsonSerializer.Serialize(_dto, AppJsonContext.Default.ScholarshipDto);
}
// Ejecutar: dotnet run -c Release
```

## NBomber Load Test

```csharp
var scenario = Scenario.Create("get_scholarships", async context =>
{
    var response = await httpClient.GetAsync("/api/scholarships");
    return response.IsSuccessStatusCode ? Response.Ok() : Response.Fail();
})
.WithLoadSimulations(
    Simulation.Inject(rate: 50, interval: TimeSpan.FromSeconds(1), during: TimeSpan.FromMinutes(2)));

NBomberRunner.RegisterScenarios(scenario).Run();
```

---

*Pattern v3.1.0*
