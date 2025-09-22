# CollectiveInference

A distributed AI inference network where community members contribute GPU resources to run AI models and earn tokens for processing inference requests.

## Features

- **GPU Resource Registration**: Providers register their compute capacity and hourly rates
- **Model Type Support**: Supports various AI models with different GPU requirements
- **Automated Matching**: Matches inference requests with suitable providers
- **Payment Escrow**: Secure payment system with automatic distribution
- **Reputation System**: Providers build reputation through successful completions
- **Flexible Availability**: Providers can toggle availability on/off

## Supported Model Types

- **LLM Small**: 4+ GPU power, 100 STX base rate
- **LLM Large**: 8+ GPU power, 300 STX base rate  
- **Image Generation**: 6+ GPU power, 200 STX base rate
- **Computer Vision**: 4+ GPU power, 150 STX base rate
- **Speech Synthesis**: 2+ GPU power, 80 STX base rate

## Contract Functions

### Public Functions
- `initialize()` - Set up supported model types and rates
- `register-provider(gpu-power, hourly-rate)` - Register as compute provider
- `request-inference(model-type, compute-hours, preferred-provider)` - Request AI inference
- `accept-request(request-id)` - Accept inference request (providers only)
- `complete-request(request-id, result-hash)` - Complete request and claim payment
- `toggle-availability()` - Toggle provider availability status

### Read-Only Functions
- `get-provider(provider)` - Get provider details and stats
- `get-request(request-id)` - Retrieve inference request information
- `get-model-config(model-type)` - Get model requirements and base rates
- `get-total-providers()` - Get total number of registered providers
- `get-request-count()` - Get total number of requests

## Usage Flow

1. GPU providers register with `register-provider()`
2. Clients request inference with `request-inference()` 
3. Providers accept requests using `accept-request()`
4. Providers complete work and submit results with `complete-request()`
5. Payments are automatically distributed and reputation updated

## Payment System

- Clients pay upfront when creating requests
- Payments held in escrow until completion
- Providers receive full payment upon successful completion
- Reputation scores increase with each successful job

## Testing

Run tests using Clarinet:
```bash
clarinet test