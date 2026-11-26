/**
 * Outils (function calling) exposés à Gemma 4 via ADK.
 * Aucun n'a besoin de clé d'API : de quoi faire une démo sans configuration.
 */
import {FunctionTool} from '@google/adk';
import {z} from 'zod';

export const getCurrentTime = new FunctionTool({
  name: 'get_current_time',
  description:
    'Returns the current date and time in a given IANA timezone (e.g. Europe/Paris, America/New_York, Asia/Tokyo).',
  parameters: z.object({
    timezone: z.string().describe('IANA timezone name, e.g. Europe/Paris'),
  }),
  execute: ({timezone}) => {
    try {
      const datetime = new Intl.DateTimeFormat('fr-FR', {
        dateStyle: 'full',
        timeStyle: 'long',
        timeZone: timezone,
      }).format(new Date());
      return {status: 'success', timezone, datetime};
    } catch {
      return {status: 'error', error: `Unknown timezone: ${timezone}`};
    }
  },
});

// Codes météo WMO utilisés par Open-Meteo (https://open-meteo.com/en/docs).
const WEATHER_CODES: Record<number, string> = {
  0: 'clear sky', 1: 'mainly clear', 2: 'partly cloudy', 3: 'overcast',
  45: 'fog', 48: 'rime fog', 51: 'light drizzle', 53: 'drizzle', 55: 'dense drizzle',
  61: 'light rain', 63: 'rain', 65: 'heavy rain', 71: 'light snow', 73: 'snow',
  75: 'heavy snow', 80: 'rain showers', 81: 'heavy rain showers', 82: 'violent rain showers',
  95: 'thunderstorm', 96: 'thunderstorm with hail', 99: 'thunderstorm with heavy hail',
};

export const getWeather = new FunctionTool({
  name: 'get_weather',
  description: 'Returns the current weather for a city (temperature, wind, humidity, conditions).',
  parameters: z.object({
    city: z.string().describe('City name, e.g. Nantes'),
  }),
  execute: async ({city}) => {
    const geoUrl = new URL('https://geocoding-api.open-meteo.com/v1/search');
    geoUrl.search = new URLSearchParams({name: city, count: '1', language: 'fr'}).toString();
    const geo = (await (await fetch(geoUrl)).json()) as {
      results?: {name: string; country: string; latitude: number; longitude: number}[];
    };
    const place = geo.results?.[0];
    if (!place) return {status: 'error', error: `City not found: ${city}`};

    const meteoUrl = new URL('https://api.open-meteo.com/v1/forecast');
    meteoUrl.search = new URLSearchParams({
      latitude: String(place.latitude),
      longitude: String(place.longitude),
      current: 'temperature_2m,apparent_temperature,relative_humidity_2m,wind_speed_10m,weather_code',
      timezone: 'auto',
    }).toString();
    const meteo = (await (await fetch(meteoUrl)).json()) as {
      current: Record<string, number | string>;
      current_units: Record<string, string>;
    };
    const c = meteo.current;
    return {
      status: 'success',
      city: place.name,
      country: place.country,
      conditions: WEATHER_CODES[Number(c.weather_code)] ?? `WMO code ${c.weather_code}`,
      temperature: `${c.temperature_2m} ${meteo.current_units.temperature_2m}`,
      feels_like: `${c.apparent_temperature} ${meteo.current_units.apparent_temperature}`,
      humidity: `${c.relative_humidity_2m} %`,
      wind: `${c.wind_speed_10m} ${meteo.current_units.wind_speed_10m}`,
      observed_at: c.time,
    };
  },
});
