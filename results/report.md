# Lambda Cold Start Benchmark Report

Quelle: gruppierte Messungen aus `results/raw/`. 
Init Duration ist nur in Cold Starts vorhanden, in Warm-Invocations leer.


## Cold Start Init Duration p50 (ms)


### Payload 1k

| Runtime \ Memory | 512 MB | 1024 MB | 1769 MB |
|---|---|---|---|
| java-jvm | 1109.16 | 1111.99 | 1125.49 |
| java-jvm-snapstart | 940.80 | 705.19 | 658.00 |
| java-jvm-snapstart-primed | 944.68 | 696.24 | 650.12 |
| java-native | 389.55 | 386.52 | 389.98 |
| node | 320.37 | 315.64 | 319.08 |

### Payload 100k

| Runtime \ Memory | 512 MB | 1024 MB | 1769 MB |
|---|---|---|---|
| java-jvm | 1117.26 | 1087.38 | 1114.96 |
| java-jvm-snapstart | 931.49 | 715.09 | 647.38 |
| java-jvm-snapstart-primed | 939.46 | 707.27 | 653.55 |
| java-native | 389.04 | 388.55 | 391.95 |
| node | 315.90 | 317.07 | 317.49 |

### Payload 1m

| Runtime \ Memory | 512 MB | 1024 MB | 1769 MB |
|---|---|---|---|
| java-jvm | 1102.38 | 1091.82 | 1106.17 |
| java-jvm-snapstart | 949.12 | 697.72 | 625.85 |
| java-jvm-snapstart-primed | 906.56 | 714.77 | 657.17 |
| java-native | 387.32 | 391.59 | 385.73 |
| node | 318.93 | 321.45 | 320.58 |

## Cold Start Init Duration p95 (ms)


### Payload 1k

| Runtime \ Memory | 512 MB | 1024 MB | 1769 MB |
|---|---|---|---|
| java-jvm | 1434.08 | 1451.46 | 1439.01 |
| java-jvm-snapstart | 1022.01 | 871.58 | 740.27 |
| java-jvm-snapstart-primed | 1089.96 | 742.72 | 704.19 |
| java-native | 521.89 | 518.84 | 533.48 |
| node | 402.54 | 388.68 | 402.79 |

### Payload 100k

| Runtime \ Memory | 512 MB | 1024 MB | 1769 MB |
|---|---|---|---|
| java-jvm | 1447.61 | 1441.86 | 1446.15 |
| java-jvm-snapstart | 1055.85 | 853.17 | 704.23 |
| java-jvm-snapstart-primed | 1095.77 | 764.83 | 736.48 |
| java-native | 526.92 | 528.74 | 524.00 |
| node | 397.12 | 392.66 | 406.72 |

### Payload 1m

| Runtime \ Memory | 512 MB | 1024 MB | 1769 MB |
|---|---|---|---|
| java-jvm | 1422.33 | 1420.16 | 1430.48 |
| java-jvm-snapstart | 1078.27 | 775.89 | 715.02 |
| java-jvm-snapstart-primed | 1024.33 | 777.09 | 702.13 |
| java-native | 528.84 | 531.63 | 516.26 |
| node | 392.31 | 400.30 | 404.93 |

## Cold Start Total Duration p95 (ms)


### Payload 1k

| Runtime \ Memory | 512 MB | 1024 MB | 1769 MB |
|---|---|---|---|
| java-jvm | 6500.50 | 3878.10 | 2915.05 |
| java-jvm-snapstart | 10969.40 | 5854.20 | 3658.00 |
| java-jvm-snapstart-primed | 10935.80 | 5971.60 | 3928.00 |
| java-native | 576.55 | 562.55 | 574.65 |
| node | 647.20 | 511.10 | 503.55 |

### Payload 100k

| Runtime \ Memory | 512 MB | 1024 MB | 1769 MB |
|---|---|---|---|
| java-jvm | 6642.85 | 3917.60 | 2931.15 |
| java-jvm-snapstart | 11338.40 | 5915.20 | 3697.60 |
| java-jvm-snapstart-primed | 11051.00 | 5999.00 | 3976.20 |
| java-native | 589.20 | 575.40 | 574.65 |
| node | 636.55 | 522.55 | 500.65 |

### Payload 1m

| Runtime \ Memory | 512 MB | 1024 MB | 1769 MB |
|---|---|---|---|
| java-jvm | 6679.10 | 3967.55 | 2921.95 |
| java-jvm-snapstart | 11631.60 | 5980.20 | 3871.00 |
| java-jvm-snapstart-primed | 11327.40 | 6357.60 | 4018.60 |
| java-native | 659.95 | 622.30 | 589.75 |
| node | 755.70 | 555.05 | 521.55 |

## Warm Duration p50 (ms)


### Payload 1k

| Runtime \ Memory | 512 MB | 1024 MB | 1769 MB |
|---|---|---|---|
| java-jvm | 23.00 | 14.00 | 15.00 |
| java-jvm-snapstart | 51.00 | 21.00 | 17.00 |
| java-jvm-snapstart-primed | 51.00 | 22.00 | 20.00 |
| java-native | 11.00 | 11.00 | 10.00 |
| node | 10.00 | 11.00 | 10.00 |

### Payload 100k

| Runtime \ Memory | 512 MB | 1024 MB | 1769 MB |
|---|---|---|---|
| java-jvm | 29.00 | 16.00 | 15.50 |
| java-jvm-snapstart | 57.00 | 27.00 | 20.00 |
| java-jvm-snapstart-primed | 50.00 | 27.00 | 19.00 |
| java-native | 11.00 | 13.00 | 12.00 |
| node | 11.00 | 10.00 | 11.50 |

### Payload 1m

| Runtime \ Memory | 512 MB | 1024 MB | 1769 MB |
|---|---|---|---|
| java-jvm | 98.50 | 53.00 | 39.00 |
| java-jvm-snapstart | 88.00 | 41.00 | 31.00 |
| java-jvm-snapstart-primed | 102.00 | 45.00 | 31.00 |
| java-native | 58.50 | 37.00 | 27.00 |
| node | 35.50 | 20.00 | 24.00 |

## Warm Duration p99 (ms)


### Payload 1k

| Runtime \ Memory | 512 MB | 1024 MB | 1769 MB |
|---|---|---|---|
| java-jvm | 51.59 | 25.04 | 20.53 |
| java-jvm-snapstart | 110.92 | 47.76 | 34.56 |
| java-jvm-snapstart-primed | 97.80 | 43.52 | 33.12 |
| java-native | 17.06 | 12.00 | 13.00 |
| node | 22.57 | 17.55 | 13.51 |

### Payload 100k

| Runtime \ Memory | 512 MB | 1024 MB | 1769 MB |
|---|---|---|---|
| java-jvm | 52.00 | 24.51 | 22.53 |
| java-jvm-snapstart | 172.92 | 104.04 | 42.64 |
| java-jvm-snapstart-primed | 116.80 | 55.76 | 31.52 |
| java-native | 13.00 | 14.51 | 16.00 |
| node | 69.10 | 15.53 | 14.00 |

### Payload 1m

| Runtime \ Memory | 512 MB | 1024 MB | 1769 MB |
|---|---|---|---|
| java-jvm | 120.00 | 70.06 | 51.06 |
| java-jvm-snapstart | 156.52 | 118.64 | 45.80 |
| java-jvm-snapstart-primed | 171.84 | 77.76 | 43.56 |
| java-native | 92.12 | 53.12 | 41.12 |
| node | 119.51 | 52.51 | 50.08 |
