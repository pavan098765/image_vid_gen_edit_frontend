// lib/features/ai_tools/generic_tool_page.dart
// FULL THEME-AWARE REWRITE — logic unchanged, UI fully Material 3 + ColorScheme

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/app_state.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/services/auth_service.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/services/file_service.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/services/user_service.dart'
    hide userCreditsNotifier, currentUserNotifier, isLoadingUserNotifier, UserData;
import 'package:kala_ai_create_images_videos_with_ai/core/theme/app_theme.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/widgets/gradient_button.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/widgets/sign_in_prompt.dart';
import 'package:kala_ai_create_images_videos_with_ai/features/ai_tools/outpaint_canvas_page.dart';
import 'package:kala_ai_create_images_videos_with_ai/features/credits/credits_page.dart';
import 'package:kala_ai_create_images_videos_with_ai/features/result_manager/result_manager_page.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// --------------------------------------
///  GENERIC TOOL PAGE (Dynamic Version)
///  - Fully driven by tool_config.json
///  - Dynamically renders all UI elements & modes
///  - Keeps all animations, HMAC submit, job polling, etc.
/// --------------------------------------

class GenericToolConfig {
  final String title;
  final String model;
  final List<dynamic> inputs;
  final Map<String, dynamic>? params;
  final Map<String, dynamic>? rootParams;
  final Map<String, dynamic>? modes;
  final List<dynamic>? elements;
  final String outputType;
  final int cost;
  final int costUpscale;
  final int offer;
  // New fields for model selection
  final List<Map<String, dynamic>>? models;
  final String? defaultModel;

  const GenericToolConfig({
    required this.title,
    required this.model,
    required this.inputs,
    this.params,
    this.rootParams,
    this.modes,
    this.elements,
    required this.outputType,
    this.cost = 0,
    this.costUpscale = 0,
    this.offer = 0,
    this.models,
    this.defaultModel,
  });

  /// Check if multiple models are available
  bool get hasMultipleModels => models != null && models!.length > 1;

  // Optional: helpful for serialization (tool_config parsing)
  factory GenericToolConfig.fromJson(Map<String, dynamic> json) {
    return GenericToolConfig(
      title: json["title"] ?? "",
      model: json["model"] ?? "",
      inputs: json["inputs"] ?? [],
      params: (json["params"] ?? {}) as Map<String, dynamic>,
      rootParams: (json["root_params"] ?? {}) as Map<String, dynamic>,
      modes: (json["modes"] ?? {}) as Map<String, dynamic>,
      elements: json["elements"] ?? [],
      outputType: json["outputType"] ?? "image",
      models: json["models"] != null
          ? List<Map<String, dynamic>>.from(json["models"])
          : null,
      defaultModel: json["defaultModel"],
    );
  }
}

/// --------------------------------------
///  PROMPT TEMPLATES SYSTEM
///  - Predefined templates to help users get started
///  - Organized by category and compatible modes
/// --------------------------------------

class PromptTemplate {
  final String id;
  final String title;
  final String prompt;
  final String category;
  final String icon; // emoji or lucide icon name
  final String? preview; // optional preview image URL
  final List<String> compatibleModes; // e.g., ['text_to_image', 'text_to_video']
  final List<String> tags;

  const PromptTemplate({
    required this.id,
    required this.title,
    required this.prompt,
    required this.category,
    required this.icon,
    this.preview,
    required this.compatibleModes,
    this.tags = const [],
  });
}

/// Template categories with metadata
class TemplateCategory {
  final String id;
  final String name;
  final String icon;
  final Color color;
  
  const TemplateCategory({
    required this.id,
    required this.name,
    required this.icon,
    required this.color,
  });
}

/// All template categories
const List<TemplateCategory> templateCategories = [
  TemplateCategory(id: 'popular', name: 'Popular', icon: '🔥', color: Color(0xFFFF6B6B)),
  TemplateCategory(id: 'art_styles', name: 'Art Styles', icon: '🎨', color: Color(0xFF8B5CF6)),
  TemplateCategory(id: 'photography', name: 'Photography', icon: '📸', color: Color(0xFF3B82F6)),
  TemplateCategory(id: 'fantasy', name: 'Fantasy', icon: '🧙', color: Color(0xFF10B981)),
  TemplateCategory(id: 'portraits', name: 'Portraits', icon: '👤', color: Color(0xFFF59E0B)),
  TemplateCategory(id: 'landscapes', name: 'Landscapes', icon: '🏔️', color: Color(0xFF06B6D4)),
  TemplateCategory(id: 'anime', name: 'Anime', icon: '🎌', color: Color(0xFFEC4899)),
  TemplateCategory(id: 'video', name: 'Video', icon: '🎬', color: Color(0xFFEF4444)),
];

/// Comprehensive list of prompt templates
const List<PromptTemplate> allPromptTemplates = [
  // --- POPULAR ---
  PromptTemplate(
    id: 'cinematic_portrait',
    title: 'Cinematic Portrait',
    prompt: 'Cinematic portrait photography, dramatic lighting, shallow depth of field, professional studio lighting, 8K resolution, highly detailed skin texture',
    category: 'popular',
    icon: '🎬',
    compatibleModes: ['text_to_image', 'image_to_image'],
    tags: ['portrait', 'cinematic', 'professional'],
  ),
  PromptTemplate(
    id: 'magical_forest',
    title: 'Magical Forest',
    prompt: 'Enchanted forest with glowing mushrooms, mystical fog, ethereal light rays piercing through ancient trees, fantasy atmosphere, magical particles floating in the air',
    category: 'popular',
    icon: '🌲',
    compatibleModes: ['text_to_image', 'text_to_video'],
    tags: ['fantasy', 'nature', 'mystical'],
  ),
  PromptTemplate(
    id: 'neon_cyberpunk',
    title: 'Neon Cyberpunk',
    prompt: 'Cyberpunk city street at night, neon signs reflecting on wet pavement, futuristic architecture, holographic advertisements, rain-soaked atmosphere, blade runner style',
    category: 'popular',
    icon: '🌃',
    compatibleModes: ['text_to_image', 'text_to_video', 'image_to_video'],
    tags: ['cyberpunk', 'neon', 'futuristic'],
  ),
  PromptTemplate(
    id: 'anime_hero',
    title: 'Anime Hero',
    prompt: 'Anime character with dynamic pose, wind-swept hair, glowing aura, detailed anime art style, vibrant colors, dramatic action scene, manga illustration quality',
    category: 'popular',
    icon: '⚡',
    compatibleModes: ['text_to_image', 'image_to_image'],
    tags: ['anime', 'action', 'character'],
  ),
  
  // --- ART STYLES ---
  PromptTemplate(
    id: 'oil_painting',
    title: 'Classic Oil Painting',
    prompt: 'Classical oil painting style, rich brush strokes, Renaissance lighting, museum quality artwork, masterful technique, fine art gallery piece',
    category: 'art_styles',
    icon: '🖼️',
    compatibleModes: ['text_to_image', 'image_to_image'],
    tags: ['oil painting', 'classical', 'fine art'],
  ),
  PromptTemplate(
    id: 'watercolor',
    title: 'Watercolor Art',
    prompt: 'Delicate watercolor painting, soft color blends, gentle brush strokes, artistic paper texture, dreamy atmosphere, watercolor illustration style',
    category: 'art_styles',
    icon: '🎨',
    compatibleModes: ['text_to_image', 'image_to_image'],
    tags: ['watercolor', 'soft', 'artistic'],
  ),
  PromptTemplate(
    id: 'digital_art',
    title: 'Digital Art',
    prompt: 'High quality digital art, crisp details, vibrant digital painting, professional concept art, trending on ArtStation, digital illustration masterpiece',
    category: 'art_styles',
    icon: '💻',
    compatibleModes: ['text_to_image', 'image_to_image'],
    tags: ['digital', 'modern', 'concept art'],
  ),
  PromptTemplate(
    id: 'pop_art',
    title: 'Pop Art Style',
    prompt: 'Bold pop art style, Andy Warhol inspired, bright contrasting colors, halftone dots, comic book aesthetic, retro 60s vibes',
    category: 'art_styles',
    icon: '🎭',
    compatibleModes: ['text_to_image', 'image_to_image'],
    tags: ['pop art', 'retro', 'bold'],
  ),
  PromptTemplate(
    id: 'impressionist',
    title: 'Impressionist',
    prompt: 'Impressionist painting style, visible brush strokes, light and color emphasis, Claude Monet inspired, soft atmospheric effects, plein air quality',
    category: 'art_styles',
    icon: '🌸',
    compatibleModes: ['text_to_image', 'image_to_image'],
    tags: ['impressionist', 'monet', 'artistic'],
  ),
  PromptTemplate(
    id: 'minimalist',
    title: 'Minimalist',
    prompt: 'Clean minimalist design, simple geometric shapes, limited color palette, negative space, modern aesthetic, elegant simplicity',
    category: 'art_styles',
    icon: '⬜',
    compatibleModes: ['text_to_image', 'image_to_image'],
    tags: ['minimalist', 'clean', 'modern'],
  ),
  
  // --- PHOTOGRAPHY ---
  PromptTemplate(
    id: 'studio_portrait',
    title: 'Studio Portrait',
    prompt: 'Professional studio portrait, softbox lighting, clean background, commercial photography quality, sharp focus on eyes, beauty retouching',
    category: 'photography',
    icon: '📷',
    compatibleModes: ['text_to_image', 'image_to_image'],
    tags: ['portrait', 'studio', 'professional'],
  ),
  PromptTemplate(
    id: 'golden_hour',
    title: 'Golden Hour',
    prompt: 'Golden hour photography, warm sunset lighting, lens flare, magical hour atmosphere, professional outdoor photography, natural golden tones',
    category: 'photography',
    icon: '🌅',
    compatibleModes: ['text_to_image', 'image_to_image', 'text_to_video'],
    tags: ['sunset', 'warm', 'outdoor'],
  ),
  PromptTemplate(
    id: 'black_white',
    title: 'Black & White',
    prompt: 'Dramatic black and white photography, high contrast, fine art monochrome, rich tonal range, Ansel Adams style, timeless elegance',
    category: 'photography',
    icon: '⚫',
    compatibleModes: ['text_to_image', 'image_to_image'],
    tags: ['monochrome', 'classic', 'dramatic'],
  ),
  PromptTemplate(
    id: 'macro',
    title: 'Macro Photography',
    prompt: 'Extreme macro photography, incredible detail, shallow depth of field, water droplets, nature close-up, scientific precision, vivid textures',
    category: 'photography',
    icon: '🔬',
    compatibleModes: ['text_to_image', 'image_to_image'],
    tags: ['macro', 'detail', 'nature'],
  ),
  PromptTemplate(
    id: 'street_photo',
    title: 'Street Photography',
    prompt: 'Candid street photography, urban environment, authentic moment captured, natural lighting, documentary style, storytelling composition',
    category: 'photography',
    icon: '🚶',
    compatibleModes: ['text_to_image', 'image_to_image'],
    tags: ['street', 'candid', 'urban'],
  ),
  
  // --- FANTASY ---
  PromptTemplate(
    id: 'dragon',
    title: 'Majestic Dragon',
    prompt: 'Majestic dragon with iridescent scales, breathing fire, perched on mountain peak, epic fantasy art, dramatic lighting, detailed creature design',
    category: 'fantasy',
    icon: '🐉',
    compatibleModes: ['text_to_image', 'text_to_video'],
    tags: ['dragon', 'epic', 'creature'],
  ),
  PromptTemplate(
    id: 'fairy',
    title: 'Ethereal Fairy',
    prompt: 'Delicate fairy with luminescent wings, surrounded by glowing flowers, magical forest setting, fantasy art, ethereal lighting, whimsical atmosphere',
    category: 'fantasy',
    icon: '🧚',
    compatibleModes: ['text_to_image', 'image_to_image'],
    tags: ['fairy', 'magical', 'whimsical'],
  ),
  PromptTemplate(
    id: 'wizard',
    title: 'Powerful Wizard',
    prompt: 'Ancient wizard casting spell, magical energy swirling, mystical runes glowing, dramatic cape flowing, epic fantasy character, detailed robes and staff',
    category: 'fantasy',
    icon: '🧙',
    compatibleModes: ['text_to_image', 'image_to_image', 'text_to_video'],
    tags: ['wizard', 'magic', 'character'],
  ),
  PromptTemplate(
    id: 'castle',
    title: 'Fantasy Castle',
    prompt: 'Magnificent fantasy castle on floating island, waterfalls cascading into clouds, magical architecture, ethereal atmosphere, epic fantasy landscape',
    category: 'fantasy',
    icon: '🏰',
    compatibleModes: ['text_to_image', 'text_to_video'],
    tags: ['castle', 'landscape', 'epic'],
  ),
  
  // --- PORTRAITS ---
  PromptTemplate(
    id: 'glamour',
    title: 'Glamour Portrait',
    prompt: 'Glamorous portrait, perfect makeup, beauty lighting, fashion magazine quality, flawless skin, professional retouching, high fashion style',
    category: 'portraits',
    icon: '💄',
    compatibleModes: ['text_to_image', 'image_to_image'],
    tags: ['glamour', 'beauty', 'fashion'],
  ),
  PromptTemplate(
    id: 'character_portrait',
    title: 'Character Portrait',
    prompt: 'Detailed character portrait, expressive eyes, personality-rich expression, professional lighting, game character quality, intricate details',
    category: 'portraits',
    icon: '🎭',
    compatibleModes: ['text_to_image', 'image_to_image'],
    tags: ['character', 'expressive', 'detailed'],
  ),
  PromptTemplate(
    id: 'royal_portrait',
    title: 'Royal Portrait',
    prompt: 'Regal royal portrait, ornate clothing, crown jewels, Renaissance style, noble bearing, oil painting aesthetic, museum masterpiece quality',
    category: 'portraits',
    icon: '👑',
    compatibleModes: ['text_to_image', 'image_to_image'],
    tags: ['royal', 'classical', 'elegant'],
  ),
  
  // --- LANDSCAPES ---
  PromptTemplate(
    id: 'mountain_vista',
    title: 'Mountain Vista',
    prompt: 'Breathtaking mountain landscape, snow-capped peaks, dramatic clouds, alpine meadows, professional landscape photography, panoramic view',
    category: 'landscapes',
    icon: '🏔️',
    compatibleModes: ['text_to_image', 'text_to_video'],
    tags: ['mountain', 'nature', 'panoramic'],
  ),
  PromptTemplate(
    id: 'ocean_sunset',
    title: 'Ocean Sunset',
    prompt: 'Stunning ocean sunset, vibrant orange and purple sky, calm waves reflecting colors, peaceful beach scene, professional seascape photography',
    category: 'landscapes',
    icon: '🌊',
    compatibleModes: ['text_to_image', 'text_to_video', 'image_to_video'],
    tags: ['ocean', 'sunset', 'peaceful'],
  ),
  PromptTemplate(
    id: 'aurora',
    title: 'Northern Lights',
    prompt: 'Spectacular aurora borealis, dancing green and purple lights, starry night sky, snow-covered landscape, Iceland scenery, long exposure photography',
    category: 'landscapes',
    icon: '🌌',
    compatibleModes: ['text_to_image', 'text_to_video'],
    tags: ['aurora', 'night', 'spectacular'],
  ),
  PromptTemplate(
    id: 'tropical',
    title: 'Tropical Paradise',
    prompt: 'Pristine tropical beach, crystal clear turquoise water, white sand, palm trees, paradise island, travel photography, vacation vibes',
    category: 'landscapes',
    icon: '🏝️',
    compatibleModes: ['text_to_image', 'text_to_video'],
    tags: ['tropical', 'beach', 'paradise'],
  ),
  
  // --- ANIME ---
  PromptTemplate(
    id: 'anime_portrait',
    title: 'Anime Portrait',
    prompt: 'Beautiful anime character portrait, large expressive eyes, detailed hair, soft shading, high quality anime art, visual novel style',
    category: 'anime',
    icon: '👧',
    compatibleModes: ['text_to_image', 'image_to_image'],
    tags: ['anime', 'portrait', 'cute'],
  ),
  PromptTemplate(
    id: 'anime_action',
    title: 'Anime Action Scene',
    prompt: 'Dynamic anime action scene, speed lines, energy effects, dramatic pose, shounen manga style, intense battle moment, detailed animation quality',
    category: 'anime',
    icon: '💥',
    compatibleModes: ['text_to_image', 'image_to_image'],
    tags: ['anime', 'action', 'dynamic'],
  ),
  PromptTemplate(
    id: 'anime_landscape',
    title: 'Anime Landscape',
    prompt: 'Beautiful anime background art, Studio Ghibli inspired, lush scenery, dreamy clouds, magical atmosphere, detailed environment art',
    category: 'anime',
    icon: '🌸',
    compatibleModes: ['text_to_image', 'text_to_video'],
    tags: ['anime', 'landscape', 'ghibli'],
  ),
  PromptTemplate(
    id: 'chibi',
    title: 'Chibi Style',
    prompt: 'Adorable chibi character, big head small body, kawaii style, cute expression, pastel colors, mascot design quality',
    category: 'anime',
    icon: '🥰',
    compatibleModes: ['text_to_image', 'image_to_image'],
    tags: ['chibi', 'cute', 'kawaii'],
  ),
  
  // --- VIDEO ---
  PromptTemplate(
    id: 'cinematic_pan',
    title: 'Cinematic Pan',
    prompt: 'Smooth cinematic camera pan across epic landscape, golden hour lighting, film grain, movie quality, dramatic reveal, professional cinematography',
    category: 'video',
    icon: '🎥',
    compatibleModes: ['text_to_video', 'image_to_video'],
    tags: ['cinematic', 'pan', 'smooth'],
  ),
  PromptTemplate(
    id: 'timelapse',
    title: 'Timelapse Style',
    prompt: 'Stunning timelapse video, clouds moving rapidly, changing light, day to night transition, hyperlapse quality, smooth motion',
    category: 'video',
    icon: '⏱️',
    compatibleModes: ['text_to_video'],
    tags: ['timelapse', 'clouds', 'motion'],
  ),
  PromptTemplate(
    id: 'slow_motion',
    title: 'Slow Motion',
    prompt: 'Dramatic slow motion footage, water droplets splashing, fabric flowing gracefully, high frame rate quality, artistic slow-mo effect',
    category: 'video',
    icon: '🐌',
    compatibleModes: ['text_to_video', 'image_to_video'],
    tags: ['slow motion', 'dramatic', 'artistic'],
  ),
  PromptTemplate(
    id: 'animation_loop',
    title: 'Seamless Loop',
    prompt: 'Perfectly looping animation, subtle continuous movement, ambient atmosphere, calm aesthetic, seamless transition, satisfying loop',
    category: 'video',
    icon: '🔄',
    compatibleModes: ['text_to_video', 'image_to_video'],
    tags: ['loop', 'animation', 'seamless'],
  ),
];

/// --------------------------------------
///  PROMPT HELPER CHIPS
///  - Quick tags to append to prompts
/// --------------------------------------

class PromptChip {
  final String label;
  final String snippet;
  final String icon;
  
  const PromptChip({
    required this.label,
    required this.snippet,
    required this.icon,
  });
}

const List<PromptChip> promptHelperChips = [
  PromptChip(label: 'Cinematic', snippet: 'cinematic lighting, film grain', icon: '🎬'),
  PromptChip(label: 'Anime', snippet: 'anime style, vibrant colors', icon: '🎌'),
  PromptChip(label: 'Portrait', snippet: 'portrait photography, sharp focus', icon: '👤'),
  PromptChip(label: 'Soft Light', snippet: 'soft diffused lighting, gentle shadows', icon: '💡'),
  PromptChip(label: 'High Detail', snippet: '8K, ultra detailed, intricate details', icon: '🔍'),
  PromptChip(label: 'Studio', snippet: 'professional studio lighting, clean background', icon: '📸'),
  PromptChip(label: 'Dramatic', snippet: 'dramatic lighting, high contrast', icon: '🌟'),
  PromptChip(label: 'Dreamy', snippet: 'dreamy atmosphere, ethereal glow', icon: '✨'),
  PromptChip(label: 'Vintage', snippet: 'vintage aesthetic, retro film look', icon: '📼'),
  PromptChip(label: 'Neon', snippet: 'neon lights, cyberpunk vibes', icon: '🌃'),
  PromptChip(label: 'Nature', snippet: 'natural lighting, outdoor setting', icon: '🌿'),
  PromptChip(label: 'Minimal', snippet: 'minimalist, clean composition', icon: '⬜'),
];

/// --------------------------------------
///  STYLE PRESETS (Visual Styles)
///  - Pre-configured style snippets with previews
/// --------------------------------------

class StylePreset {
  final String id;
  final String name;
  final String category;
  final String promptSnippet;
  final String icon; // emoji fallback
  final String? previewUrl; // preview image URL
  final bool isFeatured;
  
  const StylePreset({
    required this.id,
    required this.name,
    required this.category,
    required this.promptSnippet,
    required this.icon,
    this.previewUrl,
    this.isFeatured = false,
  });
}

const List<String> styleCategories = ['All', 'Favorite', 'Fun', 'Realistic', 'Painting', 'Anime', 'Cinematic'];

const List<StylePreset> allStylePresets = [
  // Fun
  StylePreset(
    id: 'cartoon_3d', name: '3D Cartoon', category: 'Fun',
    promptSnippet: 'Pixar 3D animation style, colorful, rounded shapes, playful lighting',
    icon: '🎪', isFeatured: true,
  ),
  StylePreset(
    id: 'comic_book', name: 'Comic Book', category: 'Fun',
    promptSnippet: 'comic book style, bold outlines, halftone dots, speech bubbles aesthetic',
    icon: '💥',
  ),
  StylePreset(
    id: 'clay_render', name: 'Clay Render', category: 'Fun',
    promptSnippet: 'claymation style, soft clay texture, stop motion aesthetic, handcrafted look',
    icon: '🎨',
  ),
  StylePreset(
    id: 'sticker', name: 'Sticker Style', category: 'Fun',
    promptSnippet: 'cute sticker design, white outline, kawaii aesthetic, glossy finish',
    icon: '🏷️',
  ),
  
  // Realistic
  StylePreset(
    id: 'photo_real', name: 'Photorealistic', category: 'Realistic',
    promptSnippet: 'photorealistic, DSLR quality, natural lighting, 8K resolution, sharp details',
    icon: '📷', isFeatured: true,
  ),
  StylePreset(
    id: 'product_shot', name: 'Product Shot', category: 'Realistic',
    promptSnippet: 'professional product photography, studio lighting, clean white background',
    icon: '🛍️',
  ),
  StylePreset(
    id: 'fashion', name: 'Fashion Editorial', category: 'Realistic',
    promptSnippet: 'high fashion editorial, Vogue magazine quality, dramatic pose, designer aesthetic',
    icon: '👗',
  ),
  StylePreset(
    id: 'documentary', name: 'Documentary', category: 'Realistic',
    promptSnippet: 'documentary photography style, candid moment, natural light, authentic',
    icon: '🎞️',
  ),
  
  // Painting
  StylePreset(
    id: 'oil_classic', name: 'Oil Painting', category: 'Painting',
    promptSnippet: 'classical oil painting, rich brush strokes, Renaissance masters style, museum quality',
    icon: '🖼️', isFeatured: true,
  ),
  StylePreset(
    id: 'watercolor', name: 'Watercolor', category: 'Painting',
    promptSnippet: 'watercolor painting, soft color blends, paper texture, artistic drips',
    icon: '🎨',
  ),
  StylePreset(
    id: 'impressionist', name: 'Impressionist', category: 'Painting',
    promptSnippet: 'impressionist painting, visible brush strokes, light and color emphasis, Monet style',
    icon: '🌸',
  ),
  StylePreset(
    id: 'digital_art', name: 'Digital Art', category: 'Painting',
    promptSnippet: 'professional digital art, trending on ArtStation, concept art quality',
    icon: '💻',
  ),
  
  // Anime
  StylePreset(
    id: 'anime_modern', name: 'Modern Anime', category: 'Anime',
    promptSnippet: 'modern anime style, detailed shading, vibrant colors, high quality animation',
    icon: '🎌', isFeatured: true,
  ),
  StylePreset(
    id: 'ghibli', name: 'Studio Ghibli', category: 'Anime',
    promptSnippet: 'Studio Ghibli style, Hayao Miyazaki aesthetic, magical realism, detailed backgrounds',
    icon: '🏯',
  ),
  StylePreset(
    id: 'manga', name: 'Manga Panel', category: 'Anime',
    promptSnippet: 'manga illustration style, black and white, screentones, dynamic composition',
    icon: '📖',
  ),
  StylePreset(
    id: 'chibi', name: 'Chibi', category: 'Anime',
    promptSnippet: 'chibi style, cute proportions, big head small body, kawaii expressions',
    icon: '🥰',
  ),
  
  // Cinematic
  StylePreset(
    id: 'film_noir', name: 'Film Noir', category: 'Cinematic',
    promptSnippet: 'film noir style, black and white, dramatic shadows, 1940s detective aesthetic',
    icon: '🎬', isFeatured: true,
  ),
  StylePreset(
    id: 'blockbuster', name: 'Blockbuster', category: 'Cinematic',
    promptSnippet: 'Hollywood blockbuster look, epic scale, cinematic color grading, anamorphic lens',
    icon: '🎥',
  ),
  StylePreset(
    id: 'scifi', name: 'Sci-Fi Epic', category: 'Cinematic',
    promptSnippet: 'science fiction aesthetic, futuristic technology, epic space opera, blade runner vibes',
    icon: '🚀',
  ),
  StylePreset(
    id: 'horror', name: 'Horror', category: 'Cinematic',
    promptSnippet: 'horror movie aesthetic, unsettling atmosphere, dark shadows, eerie lighting',
    icon: '👻',
  ),
];

/// --------------------------------------
///  ADVANCED SETTINGS MODEL
/// --------------------------------------

class AdvancedSettings {
  bool enhancePrompt;
  bool upscaleOutput;
  String quality; // 'Low', 'Medium', 'High'
  String aspectRatio; // 'Default', '1:1', '9:16', '16:9', '4:3', '3:4'
  int variations; // 1-4
  int videoDuration; // 3, 5, 8 seconds
  double cfgScale; // 0.1 - 15.0
  
  AdvancedSettings({
    this.enhancePrompt = false,
    this.upscaleOutput = false,
    this.quality = 'High',
    this.aspectRatio = 'Default',
    this.variations = 1,
    this.videoDuration = 5,
    this.cfgScale = 1.0,
  });
  
  AdvancedSettings copyWith({
    bool? enhancePrompt,
    bool? upscaleOutput,
    String? quality,
    String? aspectRatio,
    int? variations,
    int? videoDuration,
    double? cfgScale,
  }) {
    return AdvancedSettings(
      enhancePrompt: enhancePrompt ?? this.enhancePrompt,
      upscaleOutput: upscaleOutput ?? this.upscaleOutput,
      quality: quality ?? this.quality,
      aspectRatio: aspectRatio ?? this.aspectRatio,
      variations: variations ?? this.variations,
      cfgScale: cfgScale ?? this.cfgScale,
      videoDuration: videoDuration ?? this.videoDuration,
    );
  }
}

class GenericToolPage extends StatefulWidget {
  final GenericToolConfig config;
  final String? restoreJobId;
  const GenericToolPage({
    super.key,
    required this.config,
    this.restoreJobId,
  });

  static Widget restoreFromJob({
    required GenericToolConfig config,
    required String jobId,
  }) {
    return GenericToolPage(config: config, restoreJobId: jobId);
  }

  @override
  State<GenericToolPage> createState() => _GenericToolPageState();
}

class _GenericToolPageState extends State<GenericToolPage>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final picker = ImagePicker();
  final Map<String, dynamic> _inputs = {};
  bool _loading = false;
  bool _autoOpenMaskAfterPick = false;
  String? _selectedModeKey;
  String? _activeJobId;
  bool _fetchingResult = false;
  
  // Track image processing state to prevent race conditions
  bool _isProcessingImage = false;
  int _imageProcessingVersion = 0; // Increment to invalidate stale operations

  // for multi-image preview
  late PageController _previewPageController;

  // Controllers
  final TextEditingController _promptController = TextEditingController();

  // -------- Prompt/Templates Tab System --------
  late TabController _promptTabController;
  int _selectedTabIndex = 0; // 0 = Prompt, 1 = Templates
  PromptTemplate? _selectedTemplate;
  String _selectedTemplateCategory = 'popular';

  // -------- Style Library --------
  String _selectedStyleCategory = 'All';
  StylePreset? _selectedStyle;
  Set<String> _favoriteStyles = {};

  // -------- Advanced Settings --------
  late AdvancedSettings _advancedSettings;

  // -------- Model Selection --------
  String? _selectedModelId;
  Map<String, dynamic>? _selectedModelData;

  // -------- Generate Button Animation --------
  late AnimationController _glowAnimationController;

  // API config
  static const String controllerUrl = "https://genedit.mooo.com";
  final AuthService _authService = AuthService();

  // -------- Upscale (2x/4x switch) --------
  int _scaleFactor = 2;
  bool _upscaleEnabled = false;

  /// Calculate the total credit cost for this job
  int _calculateTotalCost() {
    // Use model-specific cost if available
    final baseCost = _currentModelCost;
    final upscaleCost = _currentModelUpscaleCost;
    final offer = _currentModelOffer;
    final variations = _advancedSettings.variations;
    
    // Check if upscale is enabled - use advanced settings, not _inputs
    final bool isUpscaled = _advancedSettings.upscaleOutput && _scaleFactor > 1;

    // Base cost per variation
    final int basePerVariation = baseCost + (isUpscaled ? upscaleCost : 0);
    
    // Apply offer discount
    int costPerVariation = basePerVariation;
    if (offer > 0) {
      costPerVariation = (basePerVariation * (1 - offer / 100)).round();
    }
    
    // Multiply by variations
    return costPerVariation * variations;
  }

  // Dynamic element cache
  List<Map<String, dynamic>> get _currentElements {
    if (widget.config.modes != null &&
        _selectedModeKey != null &&
        widget.config.modes!.containsKey(_selectedModeKey)) {
      return List<Map<String, dynamic>>.from(
          widget.config.modes![_selectedModeKey]!["elements"] ?? []);
    }
    return List<Map<String, dynamic>>.from(widget.config.elements ?? []);
  }

  bool get _hasPrompt => widget.config.inputs.any((i) => i['id'] == 'prompt');
  bool get _hasScaleFactor =>
      widget.config.inputs.any((i) => i['id'] == 'scale_factor');

  /// Returns the effective input config for a given base input id.
  ///
  /// Some models override UI behavior (label/max) via `inputOverrides` in tool_config.json
  /// (e.g. `qwen_image_edit_2509` supports up to 3 images). We apply those overrides
  /// to the base input while keeping the *storage id* unchanged (so elements using
  /// `input_ref: "init_image"` keep working).
  Map<String, dynamic> _effectiveInputConfig(String baseId) {
    final base = Map<String, dynamic>.from(
      widget.config.inputs.firstWhere((i) => i["id"] == baseId, orElse: () => {}),
    );

    try {
      final overrides = _selectedModelData?['inputOverrides'] as Map<String, dynamic>?;
      final o = overrides != null ? overrides[baseId] : null;
      if (o is Map) {
        // Apply only UI/selection behavior overrides; keep the actual id stable.
        if (o['label'] != null) base['label'] = o['label'];
        if (o['max'] != null) base['max'] = o['max'];
        if (o['min'] != null) base['min'] = o['min'];
        // Do NOT apply o['id'] here (it is an alias used by templates/server).
      }
    } catch (_) {}

    return base;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _previewPageController = PageController();

    // Initialize tab controller for Prompt/Templates
    _promptTabController = TabController(length: 2, vsync: this);
    _promptTabController.addListener(_onTabChanged);

    // Initialize advanced settings with defaults
    _advancedSettings = AdvancedSettings();

    // Initialize glow animation for generate button
    _glowAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    // Default mode
    if (widget.config.modes != null && widget.config.modes!.isNotEmpty) {
      _selectedModeKey = widget.config.modes!.keys.first;
    }

    // Initialize selected model
    _initializeSelectedModel();

    if (widget.restoreJobId != null) {
      _activeJobId = widget.restoreJobId;
      _loading = true;
    }

    debugPrint("🔧 Config for ${widget.config.model}");
    debugPrint("  title=${widget.config.title}");
    debugPrint("  elements=${widget.config.elements?.length}");
    debugPrint("  modes=${widget.config.modes?.keys}");
    debugPrint("  models=${widget.config.models?.length ?? 0}");
  }

  /// Initialize the selected model from config
  void _initializeSelectedModel() {
    if (widget.config.models != null && widget.config.models!.isNotEmpty) {
      // Use default model if specified, otherwise first model
      final defaultId = widget.config.defaultModel ?? widget.config.model;
      _selectedModelId = defaultId;
      _selectedModelData = widget.config.models!.firstWhere(
        (m) => m['id'] == defaultId,
        orElse: () => widget.config.models!.first,
      );
    }
  }

  /// Select a different model
  void _selectModel(Map<String, dynamic> model) {
    setState(() {
      _selectedModelId = model['id'] as String;
      _selectedModelData = model;
    });
  }

  /// Get the current model's cost
  int get _currentModelCost => 
      _selectedModelData?['cost'] as int? ?? widget.config.cost;

  /// Get the current model's upscale cost
  int get _currentModelUpscaleCost => 
      _selectedModelData?['costUpscale'] as int? ?? widget.config.costUpscale;

  /// Get the current model's offer discount
  int get _currentModelOffer => 
      _selectedModelData?['offer'] as int? ?? widget.config.offer;

  void _onTabChanged() {
    if (_promptTabController.indexIsChanging) {
      setState(() {
        _selectedTabIndex = _promptTabController.index;
      });
    }
  }

  /// Get the current mode identifier for template filtering
  String get _currentModeIdentifier {
    // Check if we have a selected mode
    if (_selectedModeKey != null) {
      return _selectedModeKey!;
    }
    // Determine mode from output type and inputs
    final hasImageInput = widget.config.inputs.any((i) => i['type'] == 'image');
    final outputType = widget.config.outputType;
    
    if (outputType == 'video') {
      return hasImageInput ? 'image_to_video' : 'text_to_video';
    }
    return hasImageInput ? 'image_to_image' : 'text_to_image';
  }

  /// Get templates filtered for the current mode
  List<PromptTemplate> get _compatibleTemplates {
    final mode = _currentModeIdentifier;
    return allPromptTemplates.where((t) => 
      t.compatibleModes.contains(mode) ||
      t.compatibleModes.any((m) => mode.contains(m.split('_').last))
    ).toList();
  }

  /// Get templates by category
  List<PromptTemplate> _getTemplatesByCategory(String categoryId) {
    return _compatibleTemplates.where((t) => t.category == categoryId).toList();
  }

  /// Get available categories (only show categories with compatible templates)
  List<TemplateCategory> get _availableCategories {
    final availableIds = _compatibleTemplates.map((t) => t.category).toSet();
    return templateCategories.where((c) => availableIds.contains(c.id)).toList();
  }

  /// Select a template and auto-fill the prompt
  void _selectTemplate(PromptTemplate template) {
    setState(() {
      _selectedTemplate = template;
      _promptController.text = template.prompt;
      _inputs['prompt'] = template.prompt;
      // Switch to prompt tab to show the filled prompt
      _promptTabController.animateTo(0);
      _selectedTabIndex = 0;
    });
    
    // Show a subtle confirmation
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(LucideIcons.check, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '"${template.title}" applied! Edit the prompt if needed.',
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 2),
        backgroundColor: Theme.of(context).colorScheme.primary,
      ),
    );
  }

  /// Clear the selected template
  void _clearTemplate() {
    setState(() {
      _selectedTemplate = null;
    });
  }

  // -------- Prompt Helper Chips --------
  
  /// Append a chip's snippet to the prompt intelligently
  void _appendChipToPrompt(PromptChip chip) {
    final currentText = _promptController.text.trim();
    String newText;
    
    if (currentText.isEmpty) {
      newText = chip.snippet;
    } else if (currentText.endsWith(',')) {
      newText = '$currentText ${chip.snippet}';
    } else {
      newText = '$currentText, ${chip.snippet}';
    }
    
    _promptController.text = newText;
    _inputs['prompt'] = newText;
    setState(() {});
  }

  // -------- Style Library --------
  
  /// Get styles filtered by category
  List<StylePreset> _getStylesByCategory(String category) {
    if (category == 'All') {
      return allStylePresets;
    }
    if (category == 'Favorite') {
      return allStylePresets.where((s) => _favoriteStyles.contains(s.id)).toList();
    }
    return allStylePresets.where((s) => s.category == category).toList();
  }

  /// Select a style and apply its snippet
  void _selectStyle(StylePreset style) {
    setState(() {
      // If same style is selected, deselect it
      if (_selectedStyle?.id == style.id) {
        _removeStyleFromPrompt(_selectedStyle!);
        _selectedStyle = null;
        return;
      }
      
      // Remove previous style snippet if any
      if (_selectedStyle != null) {
        _removeStyleFromPrompt(_selectedStyle!);
      }
      
      // Apply new style
      _selectedStyle = style;
      _appendStyleToPrompt(style);
    });
  }

  /// Append style snippet to prompt
  void _appendStyleToPrompt(StylePreset style) {
    final currentText = _promptController.text.trim();
    String newText;
    
    if (currentText.isEmpty) {
      newText = style.promptSnippet;
    } else if (currentText.endsWith(',')) {
      newText = '$currentText ${style.promptSnippet}';
    } else {
      newText = '$currentText, ${style.promptSnippet}';
    }
    
    _promptController.text = newText;
    _inputs['prompt'] = newText;
  }

  /// Remove style snippet from prompt
  void _removeStyleFromPrompt(StylePreset style) {
    final currentText = _promptController.text;
    final snippet = style.promptSnippet;
    
    // Try to remove the snippet with various separators
    String newText = currentText
        .replaceAll(', $snippet', '')
        .replaceAll('$snippet, ', '')
        .replaceAll(snippet, '')
        .trim();
    
    // Clean up any double commas or trailing commas
    newText = newText.replaceAll(', ,', ',').replaceAll(RegExp(r',\s*$'), '');
    
    _promptController.text = newText;
    _inputs['prompt'] = newText;
  }

  /// Toggle favorite status for a style
  void _toggleFavoriteStyle(String styleId) {
    setState(() {
      if (_favoriteStyles.contains(styleId)) {
        _favoriteStyles.remove(styleId);
      } else {
        _favoriteStyles.add(styleId);
      }
    });
  }

  /// Apply random style
  void _applyRandomStyle() {
    final random = Random();
    final randomStyle = allStylePresets[random.nextInt(allStylePresets.length)];
    _selectStyle(randomStyle);
    
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(LucideIcons.shuffle, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Text('Random style: ${randomStyle.name}'),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // -------- Advanced Settings --------
  
  /// Show advanced settings bottom sheet
  void _showAdvancedSettings() {
    // ✅ Unfocus any text field to prevent keyboard from re-opening after closing
    FocusScope.of(context).unfocus();
    
    final cs = Theme.of(context).colorScheme;
    // Use viewPadding (device safe area), not padding, for a tighter footer.
    final safeBottom = MediaQuery.of(context).viewPadding.bottom;
    
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          return Container(
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Handle bar (fixed at top)
                Padding(
                  padding: const EdgeInsets.only(top: 12, bottom: 8),
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: cs.outlineVariant.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                
                // Scrollable content
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Title
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: cs.primary.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(LucideIcons.settings, color: cs.primary, size: 22),
                            ),
                            const SizedBox(width: 14),
                            Text(
                              'Advanced Settings',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: cs.onSurface,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        
                        // Model Selector (only if multiple models available)
                        if (widget.config.hasMultipleModels) ...[
                          _buildModelSelector(cs, setSheetState),
                          const SizedBox(height: 20),
                        ],
                        
                        // Enhance Prompt Toggle (only for models with prompt)
                        if (_hasPrompt) ...[
                          _buildSettingToggle(
                            cs: cs,
                            icon: LucideIcons.sparkles,
                            title: 'Enhance Prompt',
                            subtitle: 'AI improves your prompt automatically',
                            value: _advancedSettings.enhancePrompt,
                            onChanged: (v) {
                              setSheetState(() {
                                setState(() {
                                  _advancedSettings = _advancedSettings.copyWith(enhancePrompt: v);
                                });
                              });
                            },
                          ),
                          const SizedBox(height: 12),
                        ],
                        
                        // Upscale Toggle
                        _buildSettingToggle(
                          cs: cs,
                          icon: LucideIcons.maximize2,
                          title: 'Upscale Output',
                          subtitle: 'Higher resolution result (+5 credits)',
                          value: _advancedSettings.upscaleOutput,
                          onChanged: (v) {
                            setSheetState(() {
                              setState(() {
                                _advancedSettings = _advancedSettings.copyWith(upscaleOutput: v);
                                _upscaleEnabled = v;
                                _inputs["scale_factor"] = v ? _scaleFactor : 1.0;
                              });
                            });
                          },
                        ),
                        
                        // Upscale Factor Selector (2x/4x) - shown when upscale is enabled
                        AnimatedSize(
                          duration: const Duration(milliseconds: 200),
                          child: _advancedSettings.upscaleOutput
                              ? Padding(
                                  padding: const EdgeInsets.only(top: 12, left: 8, right: 8),
                                  child: _buildUpscaleFactorSelector(cs, setSheetState),
                                )
                              : const SizedBox.shrink(),
                        ),
                        const SizedBox(height: 16),
                        
                        // Aspect Ratio Selector
                        _buildSettingSelector(
                          cs: cs,
                          icon: LucideIcons.scaling,
                          title: 'Aspect Ratio',
                          options: ['Default', '1:1', '9:16', '16:9', '4:3', '3:4'],
                          selected: _advancedSettings.aspectRatio,
                          onChanged: (v) {
                            setSheetState(() {
                              setState(() {
                                _advancedSettings = _advancedSettings.copyWith(aspectRatio: v);
                              });
                            });
                          },
                        ),
                        const SizedBox(height: 16),
                        
                        // CFG Scale Slider
                        _buildCfgSlider(cs, setSheetState),
                        const SizedBox(height: 16),
                        
                        // Variations Slider (for image generation)
                        if (widget.config.outputType == 'image') ...[
                          _buildSettingSlider(
                            cs: cs,
                            icon: LucideIcons.copy,
                            title: 'Variations',
                            subtitle: 'Number of images to generate',
                            value: _advancedSettings.variations.toDouble(),
                            min: 1,
                            max: 4,
                            divisions: 3,
                            onChanged: (v) {
                              setSheetState(() {
                                setState(() {
                                  _advancedSettings = _advancedSettings.copyWith(variations: v.round());
                                });
                              });
                            },
                          ),
                          const SizedBox(height: 16),
                        ],
                        
                        // Duration Selector (for video generation)
                        if (widget.config.outputType == 'video') ...[
                          _buildSettingSelector(
                            cs: cs,
                            icon: LucideIcons.timer,
                            title: 'Duration',
                            options: ['3s', '5s', '8s'],
                            selected: '${_advancedSettings.videoDuration}s',
                            onChanged: (v) {
                              setSheetState(() {
                                setState(() {
                                  _advancedSettings = _advancedSettings.copyWith(
                                    videoDuration: int.parse(v.replaceAll('s', '')),
                                  );
                                });
                              });
                            },
                          ),
                          const SizedBox(height: 16),
                        ],
                      ],
                    ),
                  ),
                ),
                
                // Done button (fixed at bottom with safe area)
                Divider(height: 1, color: cs.outlineVariant.withOpacity(0.35)),
                SafeArea(
                  top: false,
                  minimum: EdgeInsets.fromLTRB(
                    20,
                    10,
                    20,
                    safeBottom > 0 ? safeBottom : 14,
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => Navigator.pop(context),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Done',
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Build toggle setting widget
  Widget _buildSettingToggle({
    required ColorScheme cs,
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: value ? cs.primaryContainer.withOpacity(0.3) : cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: value ? cs.primary.withOpacity(0.3) : cs.outlineVariant.withOpacity(0.2),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: value ? cs.primary.withOpacity(0.15) : cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 20, color: value ? cs.primary : cs.onSurfaceVariant),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: cs.onSurface,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: cs.onSurfaceVariant.withOpacity(0.7),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: cs.primary,
          ),
        ],
      ),
    );
  }

  /// Build selector setting widget
  Widget _buildSettingSelector({
    required ColorScheme cs,
    required IconData icon,
    required String title,
    required List<String> options,
    required String selected,
    required ValueChanged<String> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: cs.onSurfaceVariant),
            const SizedBox(width: 8),
            Text(
              title,
              style: TextStyle(
                color: cs.onSurface,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: cs.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: cs.outlineVariant.withOpacity(0.2)),
          ),
          padding: const EdgeInsets.all(4),
          child: Row(
            children: options.map((opt) {
              final isSelected = selected == opt;
              return Expanded(
                child: GestureDetector(
                  onTap: () => onChanged(opt),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: isSelected ? cs.primary : Colors.transparent,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Center(
                      child: Text(
                        opt,
                        style: TextStyle(
                          color: isSelected ? cs.onPrimary : cs.onSurfaceVariant,
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  /// Build slider setting widget
  Widget _buildSettingSlider({
    required ColorScheme cs,
    required IconData icon,
    required String title,
    required String subtitle,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: cs.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: cs.onSurface,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: cs.onSurfaceVariant.withOpacity(0.7),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: cs.primary.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                value.round().toString(),
                style: TextStyle(
                  color: cs.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: cs.primary,
            inactiveTrackColor: cs.outlineVariant.withOpacity(0.3),
            thumbColor: cs.primary,
            overlayColor: cs.primary.withOpacity(0.15),
          ),
          child: Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  /// Build CFG Scale slider for advanced settings
  Widget _buildCfgSlider(ColorScheme cs, StateSetter setSheetState) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(LucideIcons.sliders, size: 18, color: cs.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'CFG Scale',
                    style: TextStyle(
                      color: cs.onSurface,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    'How closely to follow prompt (1.0 = default)',
                    style: TextStyle(
                      color: cs.onSurfaceVariant.withOpacity(0.7),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: cs.primary.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _advancedSettings.cfgScale.toStringAsFixed(1),
                style: TextStyle(
                  color: cs.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: cs.primary,
            inactiveTrackColor: cs.outlineVariant.withOpacity(0.3),
            thumbColor: cs.primary,
            overlayColor: cs.primary.withOpacity(0.15),
          ),
          child: Slider(
            value: _advancedSettings.cfgScale,
            min: 0.1,
            max: 15.0,
            divisions: 149, // 0.1 increments
            onChanged: (v) {
              setSheetState(() {
                setState(() {
                  _advancedSettings = _advancedSettings.copyWith(cfgScale: double.parse(v.toStringAsFixed(1)));
                });
              });
            },
          ),
        ),
      ],
    );
  }

  /// Build upscale factor selector (2x/4x) for advanced settings
  Widget _buildUpscaleFactorSelector(ColorScheme cs, StateSetter setSheetState) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.2)),
      ),
      child: Row(
        children: [2, 4].map((scale) {
          final isSelected = _scaleFactor == scale;
          return Expanded(
            child: GestureDetector(
              onTap: () {
                setSheetState(() {
                  setState(() {
                    _scaleFactor = scale;
                    _inputs["scale_factor"] = scale;
                  });
                });
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected ? cs.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(9),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: cs.primary.withOpacity(0.3),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        LucideIcons.maximize2,
                        size: 16,
                        color: isSelected ? cs.onPrimary : cs.onSurfaceVariant,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${scale}x',
                        style: TextStyle(
                          color: isSelected ? cs.onPrimary : cs.onSurfaceVariant,
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  /// Build model selector for advanced settings
  Widget _buildModelSelector(ColorScheme cs, StateSetter setSheetState) {
    final models = widget.config.models ?? [];
    if (models.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header
        Row(
          children: [
            Icon(LucideIcons.cpu, size: 18, color: cs.onSurfaceVariant),
            const SizedBox(width: 8),
            Text(
              'AI Model',
              style: TextStyle(
                color: cs.onSurface,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Choose the AI engine for this task',
          style: TextStyle(
            color: cs.onSurfaceVariant.withOpacity(0.7),
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 12),
        
        // Model cards - horizontal scrollable
        SizedBox(
          height: 122,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: models.length,
            itemBuilder: (context, index) {
              final model = models[index];
              final isSelected = model['id'] == _selectedModelId;
              final isDefault = model['id'] == widget.config.defaultModel;
              
              return Padding(
                padding: EdgeInsets.only(
                  right: index < models.length - 1 ? 10 : 0,
                ),
                child: _buildModelCard(
                  cs: cs,
                  model: model,
                  isSelected: isSelected,
                  isDefault: isDefault,
                  onTap: () {
                    setSheetState(() {
                      _selectModel(model);
                    });
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// Build individual model card
  Widget _buildModelCard({
    required ColorScheme cs,
    required Map<String, dynamic> model,
    required bool isSelected,
    required bool isDefault,
    required VoidCallback onTap,
  }) {
    final name = model['name'] as String? ?? 'Unknown';
    final description = model['description'] as String? ?? '';
    final cost = model['cost'] as int? ?? 10;
    final offer = model['offer'] as int? ?? 0;
    final discountedCost = offer > 0 ? (cost * (1 - offer / 100)).round() : cost;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 150,
        height: 110, // Fixed height to prevent overflow
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isSelected
              ? cs.primary.withOpacity(0.12)
              : cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected
                ? cs.primary.withOpacity(0.5)
                : cs.outlineVariant.withOpacity(0.2),
            width: isSelected ? 1.5 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: cs.primary.withOpacity(0.15),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Top row: name + selection indicator
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Model name (takes remaining space)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isSelected ? cs.primary : cs.onSurface,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (isDefault)
                        Text(
                          '★ Best',
                          style: TextStyle(
                            color: cs.secondary,
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                ),
                // Check indicator
                if (isSelected)
                  Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: cs.primary,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(LucideIcons.check, size: 10, color: cs.onPrimary),
                  ),
              ],
            ),
            
            const SizedBox(height: 4),
            
            // Description - 2 lines
            Text(
              description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: cs.onSurfaceVariant.withOpacity(0.8),
                fontSize: 10,
                height: 1.2,
              ),
            ),
            
            const Spacer(),
            
            // Cost row - at bottom
            Row(
              children: [
                Icon(LucideIcons.gem, size: 13, color: cs.primary),
                const SizedBox(width: 4),
                if (offer > 0) ...[
                  Text(
                    '$cost',
                    style: TextStyle(
                      color: cs.onSurfaceVariant.withOpacity(0.5),
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      decoration: TextDecoration.lineThrough,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '$discountedCost',
                    style: TextStyle(
                      color: cs.primary,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '-$offer%',
                      style: const TextStyle(
                        color: Colors.green,
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ] else
                  Text(
                    '$cost',
                    style: TextStyle(
                      color: cs.primary,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _promptController.dispose();
    _previewPageController.dispose();
    _promptTabController.removeListener(_onTabChanged);
    _promptTabController.dispose();
    _glowAnimationController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_activeJobId != null && _loading && !_fetchingResult) {
        debugPrint("🔁 Resuming job polling after resume");
      }
    }
  }

  // -------- Validation: Check if all required inputs are filled --------
  bool _areRequiredInputsFilled() {
    // Don't allow generation while an image is being processed
    if (_isProcessingImage) return false;
    
    final elements = _currentElements;
    
    for (final element in elements) {
      final type = element["type"];
      final inputRef = element["input_ref"];
      
      // Skip elements without input_ref (like upscale_toggle, generate_button)
      if (inputRef == null) continue;
      
      // Skip optional inputs like sliders, dropdowns (they have defaults)
      if (type == "slider" || type == "dropdown") continue;
      
      switch (type) {
        case "prompt":
          // Prompt is required - always use the controller as source of truth
          final promptText = _promptController.text.trim();
          if (promptText.isEmpty) {
            return false;
          }
          break;
          
        case "image_upload":
          // Image is required - check if it exists and is not empty
          final imageData = _inputs[inputRef];
          if (imageData == null) return false;
          if (imageData is List && imageData.isEmpty) return false;
          break;
          
        case "painter":
          // Mask is required for inpainting modes
          final maskData = _inputs[inputRef];
          if (maskData == null) return false;
          break;
      }
    }
    
    return true;
  }
  
  // Get list of missing required inputs for user feedback
  List<String> _getMissingInputs() {
    final missing = <String>[];
    
    // Show processing message while image is being loaded
    if (_isProcessingImage) {
      return ["Image loading..."]; // Special message for processing state
    }
    
    final elements = _currentElements;
    
    for (final element in elements) {
      final type = element["type"];
      final inputRef = element["input_ref"];
      
      // Skip elements without input_ref
      if (inputRef == null) continue;
      
      // Skip optional inputs
      if (type == "slider" || type == "dropdown") continue;
      
      switch (type) {
        case "prompt":
          // Always use the controller as source of truth
          final promptText = _promptController.text.trim();
          if (promptText.isEmpty) {
            missing.add("Prompt");
          }
          break;
          
        case "image_upload":
          final imageData = _inputs[inputRef];
          if (imageData == null || (imageData is List && imageData.isEmpty)) {
            missing.add("Image");
          }
          break;
          
        case "painter":
          final maskData = _inputs[inputRef];
          if (maskData == null) {
            missing.add("Mask");
          }
          break;
      }
    }
    
    return missing;
  }

  // -------- Generate Button --------
  Widget _buildGenerateButton() {
    final cs = Theme.of(context).colorScheme;
    final baseCost = widget.config.cost;
    final upscaleCost = widget.config.costUpscale;
    final offer = widget.config.offer;
    final scaleFactor = _inputs["scale_factor"] ?? 1.0;

    // Calculate costs
    final int baseTotal = baseCost + ((scaleFactor > 1) ? upscaleCost : 0);
    int totalCost = baseTotal;
    if (offer > 0) {
      totalCost = (baseTotal * (1 - offer / 100)).round();
    }

    // Check if button should be enabled
    final isEnabled = _areRequiredInputsFilled();
    final missingInputs = _getMissingInputs();

    return Container(
      margin: const EdgeInsets.only(top: 20, bottom: 16),
      child: Column(
        children: [
          // Missing inputs hint (shown when button is disabled)
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            child: !isEnabled && missingInputs.isNotEmpty
                ? Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: _isProcessingImage 
                          ? cs.primaryContainer.withOpacity(0.3)
                          : cs.errorContainer.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _isProcessingImage
                            ? cs.primary.withOpacity(0.2)
                            : cs.error.withOpacity(0.2),
                      ),
                    ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                        if (_isProcessingImage)
                          SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: cs.primary.withOpacity(0.8),
                            ),
                          )
                        else
                Icon(
                            LucideIcons.alertCircle,
                            size: 16,
                            color: cs.error.withOpacity(0.8),
                ),
                const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            _isProcessingImage 
                                ? "Processing image..."
                                : "Add ${missingInputs.join(' & ')} to continue",
                              style: TextStyle(
                              color: _isProcessingImage
                                  ? cs.primary.withOpacity(0.9)
                                  : cs.error.withOpacity(0.9),
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          
          // Main generate button with integrated cost (Kala AI brand gradient)
          Opacity(
            opacity: isEnabled ? 1.0 : 0.6,
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                gradient: LinearGradient(
                  colors: isEnabled
                      ? KalaColors.brandGradient
                      : [cs.onSurfaceVariant.withOpacity(0.4), cs.onSurfaceVariant.withOpacity(0.3)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: isEnabled
                    ? [
                        BoxShadow(
                          color: KalaColors.purple.withOpacity(0.4),
                          blurRadius: 20,
                          offset: const Offset(0, 6),
                        ),
                        BoxShadow(
                          color: KalaColors.cyan.withOpacity(0.2),
                          blurRadius: 28,
                          offset: const Offset(0, 10),
                        ),
                      ]
                    : null,
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: isEnabled ? _runJob : null,
                  borderRadius: BorderRadius.circular(18),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Left: Generate text with icon
                        Icon(
                          LucideIcons.sparkles,
                          color: Colors.white,
                          size: 22,
                              ),
                        const SizedBox(width: 10),
                        const Text(
                          "Generate",
                              style: TextStyle(
                                color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.3,
                              ),
                            ),
                        
                        // Divider
                        Container(
                          margin: const EdgeInsets.symmetric(horizontal: 14),
                          height: 24,
                          width: 1,
                          color: Colors.white.withOpacity(0.3),
                        ),
                        
                        // Right: Cost display
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                LucideIcons.gem,
                                size: 16,
                                color: Colors.white.withOpacity(0.9),
                              ),
                              const SizedBox(width: 6),
                              if (offer > 0) ...[
                                Text(
                                  "$baseTotal",
                              style: TextStyle(
                                    color: Colors.white.withOpacity(0.6),
                                    fontSize: 14,
                                decoration: TextDecoration.lineThrough,
                                    decorationColor: Colors.white.withOpacity(0.6),
                                  ),
                                ),
                                const SizedBox(width: 4),
                              ],
                              Text(
                                "$totalCost",
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                              ),
                            ),
                              if (offer > 0) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 5,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.greenAccent.withOpacity(0.25),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    "-$offer%",
                              style: const TextStyle(
                                      color: Colors.greenAccent,
                                      fontSize: 11,
                                fontWeight: FontWeight.w600,
                                    ),
                              ),
                            ),
                          ],
                            ],
                        ),
                      ),
              ],
            ),
          ),
                ),
              ),
            ),
          ),
          
          // Upscale info badge (when upscale is enabled)
          if (_upscaleEnabled && upscaleCost > 0)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    LucideIcons.maximize2,
                    size: 14,
                    color: cs.primary.withOpacity(0.7),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    "${_scaleFactor}x upscale (+$upscaleCost credits)",
                      style: TextStyle(
                      color: cs.onSurfaceVariant.withOpacity(0.7),
                      fontSize: 12,
                        fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // 🖼️ BUILD UI — Scaffold + Mode Selector + Dynamic Elements
  // ----------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    cs.primary.withOpacity(0.15),
                    cs.secondary.withOpacity(0.1),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                LucideIcons.sparkles,
                size: 18,
                color: cs.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
          widget.config.title,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface,
                  fontSize: 18,
                  letterSpacing: -0.3,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        backgroundColor: cs.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: IconThemeData(color: cs.onSurface),
        actions: [
          // Credits display
          ValueListenableBuilder<int>(
            valueListenable: userCreditsNotifier,
            builder: (_, credits, __) {
              return Container(
                margin: const EdgeInsets.only(right: 12),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: cs.primaryContainer.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: cs.primary.withOpacity(0.2),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      LucideIcons.gem,
                      size: 16,
                      color: cs.primary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      credits.toString(),
                      style: TextStyle(
                        color: cs.primary,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: _buildDynamicInputScreen(),
    );
  }

  // -----------------------------------------------
  // 🧠 IMAGE PICKING & INPUT MANAGEMENT
  // -----------------------------------------------

  Future<void> _pickImageFromGallery(Map<String, dynamic> input) async {
    final id = input['id'];
    final maxCount = (input['max'] ?? 1) as int;
    final allowMulti = maxCount > 1;

    // Increment version and start processing
    final currentVersion = ++_imageProcessingVersion;
    setState(() => _isProcessingImage = true);

    try {
      if (allowMulti) {
        final files = await picker.pickMultiImage(imageQuality: 85);
        if (files.isEmpty) {
          if (mounted) setState(() => _isProcessingImage = false);
          return;
        }

        // Check if this operation is still valid (not superseded by newer pick)
        if (currentVersion != _imageProcessingVersion) {
          // A newer operation started, this one is cancelled - don't reset flag
          return;
        }

        final limited = files.take(maxCount).toList();
        final bytesList = await Future.wait(limited.map((f) async {
          final b = await f.readAsBytes();
          return _resizeImageSafe(b);
        }));

        // Check again after async operation
        if (currentVersion != _imageProcessingVersion || !mounted) {
          // A newer operation started or widget unmounted
          return;
        }

          setState(() {
            _inputs[id] = bytesList;
            _inputs["${id}_path"] = limited.first.path;
          _isProcessingImage = false;
          });
      } else {
        final file = await picker.pickImage(
            source: ImageSource.gallery, imageQuality: 85);
        if (file == null) {
          if (mounted) setState(() => _isProcessingImage = false);
          return;
        }

        // Check if this operation is still valid
        if (currentVersion != _imageProcessingVersion) {
          // A newer operation started, this one is cancelled
          return;
        }

        final bytes = await _resizeImageSafe(await file.readAsBytes());

        // Check again after async operation
        if (currentVersion != _imageProcessingVersion || !mounted) {
          // A newer operation started or widget unmounted
          return;
        }

          setState(() {
            _inputs[id] = [bytes];
            _inputs["${id}_path"] = file.path;
          _isProcessingImage = false;
          });

        if (widget.config.model == "diffusers_outpaint") {
          final result = await Navigator.push<Map<String, String>>(
            context,
            MaterialPageRoute(
              builder: (_) => OutpaintCanvasPage(imageBytes: bytes),
              fullscreenDialog: true,
            ),
          );
          if (result != null && mounted) {
            setState(() {
              _inputs["alignment"] = result["alignment"];
              _inputs["aspect_ratio"] = result["aspect_ratio"];
              _inputs["outpaint_preview"] = bytes; // keep for visual cue
            });
          }
        }

        // Automatically open mask editor for inpainting / LaMa models
        final model = widget.config.model.toLowerCase();
        final mode = _selectedModeKey?.toLowerCase() ?? "";
        final paramMode =
            (widget.config.params?["mode"]?.toString().toLowerCase() ?? "");

        if (model.contains("inpaint") ||
            model.contains("lama") ||
            mode.contains("inpaint") ||
            paramMode.contains("inpaint") ||
            paramMode.contains("lama")) {
          _autoOpenMaskAfterPick = true;
        }

        // --- Auto-open mask editor if required ---
        if (_autoOpenMaskAfterPick) {
          _autoOpenMaskAfterPick = false;
          final baseBytes = _inputs[id]?[0] as Uint8List?;
          if (baseBytes != null) {
            final mask = await _openMaskEditor(baseBytes);
            if (mask != null && mounted) {
              setState(() {
                _inputs["mask_image"] = mask;
              });
            }
          }
        }
      }
    } catch (e) {
      debugPrint("Gallery picker failed: $e");
      if (mounted) {
        setState(() => _isProcessingImage = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Failed to load image: $e")));
      }
    }
  }

  Future<void> _pickImageFromCamera(Map<String, dynamic> input) async {
    final id = input['id'];
    
    // Increment version and start processing
    final currentVersion = ++_imageProcessingVersion;
    setState(() => _isProcessingImage = true);
    
    try {
      final file =
          await picker.pickImage(source: ImageSource.camera, imageQuality: 85);
      if (file == null) {
        if (mounted) setState(() => _isProcessingImage = false);
        return;
      }

      // Check if this operation is still valid
      if (currentVersion != _imageProcessingVersion) {
        // A newer operation started, this one is cancelled
        return;
      }

      final bytes = await _resizeImageSafe(await file.readAsBytes());

      // Check again after async operation
      if (currentVersion != _imageProcessingVersion || !mounted) {
        // A newer operation started or widget unmounted
        return;
      }

        setState(() {
          _inputs[id] = [bytes];
          _inputs["${id}_path"] = file.path;
        _isProcessingImage = false;
        });

      if (widget.config.model == "diffusers_outpaint") {
        final result = await Navigator.push<Map<String, String>>(
          context,
          MaterialPageRoute(
            builder: (_) => OutpaintCanvasPage(imageBytes: bytes),
            fullscreenDialog: true,
          ),
        );
        if (result != null && mounted) {
          setState(() {
            _inputs["alignment"] = result["alignment"];
            _inputs["aspect_ratio"] = result["aspect_ratio"];
            _inputs["outpaint_preview"] = bytes; // keep for visual cue
          });
        }
      }

      // Automatically open mask editor for inpainting / LaMa models
      final model = widget.config.model.toLowerCase();
      final mode = _selectedModeKey?.toLowerCase() ?? "";
      final paramMode =
          (widget.config.params?["mode"]?.toString().toLowerCase() ?? "");

      if (model.contains("inpaint") ||
          model.contains("lama") ||
          mode.contains("inpaint") ||
          paramMode.contains("inpaint") ||
          paramMode.contains("lama")) {
        _autoOpenMaskAfterPick = true;
      }

      // --- Auto-open mask editor if required ---
      if (_autoOpenMaskAfterPick) {
        _autoOpenMaskAfterPick = false;
        final baseBytes = _inputs[id]?[0] as Uint8List?;
        if (baseBytes != null) {
          final mask = await _openMaskEditor(baseBytes);
          if (mask != null && mounted) {
            setState(() {
              _inputs["mask_image"] = mask;
            });
          }
        }
      }
    } catch (e) {
      debugPrint("Camera image failed: $e");
      if (mounted) {
        setState(() => _isProcessingImage = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("Camera capture failed: $e")));
      }
    }
  }

  Future<Uint8List> _resizeImageSafe(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final img = frame.image;
    int width = img.width;
    int height = img.height;

    // HARD CAP: keep the longer edge <= 1536px to reduce backend GPU memory use.
    // Also ensure final dimensions are multiples of 32 WITHOUT rounding up past 1536.
    const int maxDim = 1200;
    if (width > maxDim || height > maxDim) {
      final scale = maxDim / max(width, height);
      width = (width * scale).round();
      height = (height * scale).round();
    }

    // Round DOWN to nearest multiple of 32 so we never exceed maxDim after padding.
    int roundDown32(int x) => max(32, (x ~/ 32) * 32);
    final paddedW = min(maxDim, roundDown32(width));
    final paddedH = min(maxDim, roundDown32(height));

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    final paint = Paint()..color = const Color(0x00000000);
    canvas.drawRect(
        Rect.fromLTWH(0, 0, paddedW.toDouble(), paddedH.toDouble()), paint);

    // Center the scaled image within the padded canvas.
    final offsetX = (paddedW - width) / 2;
    final offsetY = (paddedH - height) / 2;

    final src =
        Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble());
    final dst = Rect.fromLTWH(
      offsetX,
      offsetY,
      width.toDouble().clamp(1, paddedW.toDouble()),
      height.toDouble().clamp(1, paddedH.toDouble()),
    );

    canvas.drawImageRect(img, src, dst, Paint());

    final finalImage = await recorder
        .endRecording()
        .toImage(paddedW, paddedH)
        .then((v) => v.toByteData(format: ui.ImageByteFormat.png));

    img.dispose();
    return finalImage!.buffer.asUint8List();
  }

  /// Theme-aware unified bottom-sheet picker
  Future<void> _pickImage(Map<String, dynamic> input) async {
    final cs = Theme.of(context).colorScheme;
    try {
      final source = await showModalBottomSheet<ImageSource>(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (_) {
          return Container(
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 20,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                    // Handle bar
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: cs.outlineVariant.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 20),
                    
                    // Title
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: cs.primary.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            LucideIcons.imagePlus,
                            color: cs.primary,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Text(
                          'Choose Image Source',
                    style: TextStyle(
                      fontSize: 18,
                            fontWeight: FontWeight.w700,
                      color: cs.onSurface,
                    ),
                  ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    
                    // Options
                    Row(
                      children: [
                        // Gallery option
                        Expanded(
                          child: _buildPickerOption(
                            icon: LucideIcons.image,
                            label: 'Gallery',
                            sublabel: 'Choose from photos',
                            color: cs.primary,
                  onTap: () => Navigator.pop(context, ImageSource.gallery),
                ),
                        ),
                        const SizedBox(width: 12),
                        
                        // Camera option
                        Expanded(
                          child: _buildPickerOption(
                            icon: LucideIcons.camera,
                            label: 'Camera',
                            sublabel: 'Take a new photo',
                            color: cs.secondary,
                  onTap: () => Navigator.pop(context, ImageSource.camera),
                          ),
                        ),
                      ],
                ),
                const SizedBox(height: 8),
              ],
                ),
              ),
            ),
          );
        },
      );

      if (source == null) return;

      if (source == ImageSource.gallery) {
        await _pickImageFromGallery(input);
      } else {
        await _pickImageFromCamera(input);
      }
    } catch (e) {
      debugPrint('❌ Error picking image: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error picking image: $e')),
        );
      }
    }
  }

  // Picker option card for bottom sheet
  Widget _buildPickerOption({
    required IconData icon,
    required String label,
    required String sublabel,
    required Color color,
    required VoidCallback onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
        border: Border.all(
              color: cs.outlineVariant.withOpacity(0.3),
            ),
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 28, color: color),
              ),
              const SizedBox(height: 12),
              Text(
                label,
                style: TextStyle(
                  color: cs.onSurface,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
          ),
              ),
              const SizedBox(height: 4),
              Text(
                sublabel,
                style: TextStyle(
                  color: cs.onSurfaceVariant.withOpacity(0.7),
                  fontSize: 12,
                ),
                textAlign: TextAlign.center,
          ),
        ],
      ),
        ),
      ),
    );
  }

  // ---------- Card (uses shared AppStyles for consistency) ----------
  Widget _buildCard({
    required Widget child,
    EdgeInsets? padding,
    EdgeInsets? margin,
    bool elevated = false,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: margin ?? const EdgeInsets.symmetric(vertical: AppStyles.spacing8),
      padding: padding ?? const EdgeInsets.all(AppStyles.spacing16),
      decoration: AppStyles.cardDecoration(cs, elevated: elevated),
      child: child,
    );
  }

  Widget _buildElement(Map<String, dynamic> e) {
    final type = e["type"];
    final ref = e["input_ref"];

    switch (type) {
      case "prompt":
        return _buildPrompt(ref);
      case "image_upload":
        return _buildImageUpload(ref);
      case "slider":
        return _buildSlider(ref);
      case "dropdown":
        return _buildDropdown(ref);
      case "painter":
        return _buildPainter(ref);
      case "generate_button":
        return _buildGenerateButton();
      default:
        return const SizedBox.shrink();
    }
  }

  // -------- Prompt with Templates Tab System --------
  Widget _buildPrompt(String ref) {
    final cs = Theme.of(context).colorScheme;
    final label = widget.config.inputs
            .firstWhere((i) => i["id"] == ref, orElse: () => {})["label"] ??
        "Describe what you want to create";

    return _buildCard(
      padding: const EdgeInsets.all(0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Tab bar header
          Container(
            decoration: BoxDecoration(
              color: cs.surfaceContainerHigh.withOpacity(0.5),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: TabBar(
              controller: _promptTabController,
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: Colors.transparent,
              indicatorPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              indicator: BoxDecoration(
                gradient: const LinearGradient(
                  colors: KalaColors.brandGradient,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: KalaColors.purple.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              labelColor: Colors.white,
              unselectedLabelColor: cs.onSurfaceVariant,
              labelStyle: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
              unselectedLabelStyle: const TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 14,
              ),
              tabs: [
                Tab(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(LucideIcons.penTool, size: 16),
                      const SizedBox(width: 6),
                      const Text('Prompt'),
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(LucideIcons.layoutGrid, size: 16),
                      const SizedBox(width: 6),
                      const Text('Templates'),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          // Tab content - only show selected tab to avoid extra space
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: _selectedTabIndex == 0
                ? _buildPromptTabContent(ref, label)
                : _buildTemplatesTabContent(),
          ),
        ],
      ),
    );
  }

  /// Build the Prompt tab content with guided input
  Widget _buildPromptTabContent(String ref, String label) {
    final cs = Theme.of(context).colorScheme;
    final promptLength = _promptController.text.length;
    final showCharCounter = promptLength > 0;
    
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Applied template/style indicator
          if (_selectedTemplate != null || _selectedStyle != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: cs.primaryContainer.withOpacity(0.3),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: cs.primary.withOpacity(0.3),
                ),
              ),
              child: Row(
                children: [
                  Text(
                    _selectedTemplate?.icon ?? _selectedStyle?.icon ?? '✨',
                    style: const TextStyle(fontSize: 16),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _selectedTemplate != null
                          ? 'Template: ${_selectedTemplate!.title}'
                          : 'Style: ${_selectedStyle!.name}',
                      style: TextStyle(
                        color: cs.primary,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: () {
                      if (_selectedTemplate != null) {
                        _clearTemplate();
                      }
                      if (_selectedStyle != null) {
                        _removeStyleFromPrompt(_selectedStyle!);
                        setState(() => _selectedStyle = null);
                      }
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        LucideIcons.x,
                        size: 16,
                        color: cs.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
          
          // Prompt text field with guided placeholder
          TextField(
            controller: _promptController,
            onChanged: (v) {
              _inputs[ref] = v;
              setState(() {}); // Trigger rebuild
            },
            maxLines: 4,
            minLines: 3,
            decoration: InputDecoration(
              hintText: 'Describe what you want, or choose a template...',
              hintStyle: TextStyle(
                color: cs.onSurfaceVariant.withOpacity(0.5),
                fontSize: 15,
              ),
              filled: true,
              fillColor: cs.surfaceContainerHigh.withOpacity(0.5),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(
                  color: cs.outlineVariant.withOpacity(0.2),
                  width: 1,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(
                  color: cs.primary.withOpacity(0.5),
                  width: 1.5,
                ),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
              suffixIcon: _promptController.text.isNotEmpty
                  ? IconButton(
                      icon: Icon(
                        LucideIcons.x,
                        size: 18,
                        color: cs.onSurfaceVariant.withOpacity(0.6),
                      ),
                      onPressed: () {
                        _promptController.clear();
                        _inputs[ref] = '';
                        _clearTemplate();
                        if (_selectedStyle != null) {
                          setState(() => _selectedStyle = null);
                        }
                        setState(() {});
                      },
                    )
                  : null,
            ),
            style: TextStyle(
              color: cs.onSurface,
              fontSize: 15,
              height: 1.5,
            ),
          ),
          
          const SizedBox(height: 8),
          
          // Example text and character counter row
          Row(
            children: [
              // Example subtext
              Expanded(
                child: Text(
                  'e.g. "Anime portrait, cinematic lighting, dramatic pose"',
                  style: TextStyle(
                    color: cs.onSurfaceVariant.withOpacity(0.5),
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
              // Character counter (only shown when typing)
              AnimatedOpacity(
                opacity: showCharCounter ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$promptLength',
                    style: TextStyle(
                      color: cs.onSurfaceVariant.withOpacity(0.6),
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 14),
          
          // Prompt helper chips section
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    LucideIcons.plus,
                    size: 14,
                    color: cs.onSurfaceVariant.withOpacity(0.7),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Quick add:',
                    style: TextStyle(
                      color: cs.onSurfaceVariant.withOpacity(0.7),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: promptHelperChips.map((chip) {
                  return InkWell(
                    onTap: () => _appendChipToPrompt(chip),
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: cs.outlineVariant.withOpacity(0.3),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            chip.icon,
                            style: const TextStyle(fontSize: 12),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            chip.label,
                            style: TextStyle(
                              color: cs.onSurface,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Build the Templates tab content with Style Library
  Widget _buildTemplatesTabContent() {
    final cs = Theme.of(context).colorScheme;
    final categories = _availableCategories;
    final templates = _getTemplatesByCategory(_selectedTemplateCategory);
    final styles = _getStylesByCategory(_selectedStyleCategory);
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ========== PROMPT TEMPLATES SECTION ==========
          Row(
            children: [
              Icon(LucideIcons.fileText, size: 16, color: cs.primary),
              const SizedBox(width: 8),
              Text(
                'Prompt Templates',
                style: TextStyle(
                  color: cs.onSurface,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          
          // Category filter chips
          SizedBox(
            height: 36,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: categories.length,
              itemBuilder: (context, index) {
                final category = categories[index];
                final isSelected = _selectedTemplateCategory == category.id;
                
                return Padding(
                  padding: EdgeInsets.only(
                    right: 8,
                    left: index == 0 ? 0 : 0,
                  ),
                  child: InkWell(
                    onTap: () {
                      setState(() {
                        _selectedTemplateCategory = category.id;
                      });
                    },
                    borderRadius: BorderRadius.circular(18),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: isSelected 
                            ? category.color.withOpacity(0.2)
                            : cs.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: isSelected 
                              ? category.color.withOpacity(0.5)
                              : cs.outlineVariant.withOpacity(0.2),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            category.icon,
                            style: const TextStyle(fontSize: 14),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            category.name,
                            style: TextStyle(
                              color: isSelected ? category.color : cs.onSurfaceVariant,
                              fontSize: 13,
                              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          
          const SizedBox(height: 12),
          
          // Template grid
          if (templates.isEmpty)
            Container(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Column(
                  children: [
                    Icon(
                      LucideIcons.searchX,
                      size: 32,
                      color: cs.onSurfaceVariant.withOpacity(0.4),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'No templates available for this mode',
                      style: TextStyle(
                        color: cs.onSurfaceVariant.withOpacity(0.6),
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1.4,
              ),
              itemCount: templates.length,
              itemBuilder: (context, index) {
                final template = templates[index];
                final isSelected = _selectedTemplate?.id == template.id;
                
                return _buildTemplateCard(template, isSelected);
              },
            ),
          
          const SizedBox(height: 24),
          
          // ========== STYLE LIBRARY SECTION ==========
          Row(
            children: [
              Icon(LucideIcons.palette, size: 16, color: cs.secondary),
              const SizedBox(width: 8),
              Text(
                'Style Library',
                style: TextStyle(
                  color: cs.onSurface,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              // Random style button
              InkWell(
                onTap: _applyRandomStyle,
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: cs.secondaryContainer.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: cs.secondary.withOpacity(0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(LucideIcons.shuffle, size: 14, color: cs.secondary),
                      const SizedBox(width: 4),
                      Text(
                        'Random',
                        style: TextStyle(
                          color: cs.secondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          
          // Style category filter
          SizedBox(
            height: 34,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: styleCategories.length,
              itemBuilder: (context, index) {
                final category = styleCategories[index];
                final isSelected = _selectedStyleCategory == category;
                
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: InkWell(
                    onTap: () {
                      setState(() {
                        _selectedStyleCategory = category;
                      });
                    },
                    borderRadius: BorderRadius.circular(16),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: isSelected 
                            ? cs.secondary.withOpacity(0.2)
                            : cs.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isSelected 
                              ? cs.secondary.withOpacity(0.5)
                              : cs.outlineVariant.withOpacity(0.2),
                        ),
                      ),
                      child: Text(
                        category,
                        style: TextStyle(
                          color: isSelected ? cs.secondary : cs.onSurfaceVariant,
                          fontSize: 12,
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          
          const SizedBox(height: 12),
          
          // Style grid
          if (styles.isEmpty && _selectedStyleCategory == 'Favorite')
            Container(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Column(
                  children: [
                    Icon(
                      LucideIcons.heart,
                      size: 32,
                      color: cs.onSurfaceVariant.withOpacity(0.4),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'No favorite styles yet',
                      style: TextStyle(
                        color: cs.onSurfaceVariant.withOpacity(0.6),
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Tap the heart on any style to save it',
                      style: TextStyle(
                        color: cs.onSurfaceVariant.withOpacity(0.4),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1.3,
              ),
              itemCount: styles.length,
              itemBuilder: (context, index) {
                final style = styles[index];
                final isSelected = _selectedStyle?.id == style.id;
                final isFavorite = _favoriteStyles.contains(style.id);
                
                return _buildStyleCard(style, isSelected, isFavorite);
              },
            ),
        ],
      ),
    );
  }

  /// Build individual style card with visual preview
  Widget _buildStyleCard(StylePreset style, bool isSelected, bool isFavorite) {
    final cs = Theme.of(context).colorScheme;
    
    // Color based on category
    final categoryColors = {
      'Fun': const Color(0xFFFF6B6B),
      'Realistic': const Color(0xFF3B82F6),
      'Painting': const Color(0xFF8B5CF6),
      'Anime': const Color(0xFFEC4899),
      'Cinematic': const Color(0xFFF59E0B),
    };
    final cardColor = categoryColors[style.category] ?? cs.secondary;
    
    return InkWell(
      onTap: () => _selectStyle(style),
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected 
                ? cardColor.withOpacity(0.6)
                : cs.outlineVariant.withOpacity(0.2),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: cardColor.withOpacity(0.25),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(13),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Background - Image or Gradient
              if (style.previewUrl != null)
                Image.network(
                  style.previewUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _buildStyleGradient(cardColor),
                )
              else
                _buildStyleGradient(cardColor),
              
              // Gradient overlay for text readability
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withOpacity(0.75),
                    ],
                    stops: const [0.35, 1.0],
                  ),
                ),
              ),
              
              // Content
              Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Top row - Icon, Featured badge, Favorite
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Style icon
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            style.icon,
                            style: const TextStyle(fontSize: 16),
                          ),
                        ),
                        // Right side - Featured or Selection indicator
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (style.isFeatured)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                margin: const EdgeInsets.only(right: 4),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [Colors.amber.shade600, Colors.orange.shade600],
                                  ),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  '★',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                  ),
                                ),
                              ),
                            if (isSelected)
                              Container(
                                padding: const EdgeInsets.all(4),
                                decoration: const BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  LucideIcons.check,
                                  size: 12,
                                  color: cardColor,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                    
                    const Spacer(),
                    
                    // Bottom content
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                style.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 1),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  style.category,
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.85),
                                    fontSize: 9,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Favorite button
                        InkWell(
                          onTap: () => _toggleFavoriteStyle(style.id),
                          borderRadius: BorderRadius.circular(14),
                          child: Container(
                            padding: const EdgeInsets.all(5),
                            decoration: BoxDecoration(
                              color: isFavorite 
                                  ? Colors.red.withOpacity(0.3)
                                  : Colors.white.withOpacity(0.15),
                              shape: BoxShape.circle,
                            ),
                            child: isFavorite
                                ? const Icon(Icons.favorite, size: 14, color: Colors.red)
                                : Icon(LucideIcons.heart, size: 14, color: Colors.white.withOpacity(0.8)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Build gradient background for style card
  Widget _buildStyleGradient(Color baseColor) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            baseColor.withOpacity(0.9),
            baseColor.withOpacity(0.5),
            Colors.black.withOpacity(0.7),
          ],
          stops: const [0.0, 0.4, 1.0],
        ),
      ),
    );
  }

  /// Build individual template card with visual preview
  Widget _buildTemplateCard(PromptTemplate template, bool isSelected) {
    final cs = Theme.of(context).colorScheme;
    final category = templateCategories.firstWhere(
      (c) => c.id == template.category,
      orElse: () => templateCategories.first,
    );
    
    return InkWell(
      onTap: () => _selectTemplate(template),
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected 
                ? category.color.withOpacity(0.6)
                : cs.outlineVariant.withOpacity(0.2),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: category.color.withOpacity(0.25),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(13),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Background - Image or Gradient
              if (template.preview != null)
                Image.network(
                  template.preview!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _buildTemplateGradient(category.color),
                )
              else
                _buildTemplateGradient(category.color),
              
              // Gradient overlay for text readability
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withOpacity(0.7),
                    ],
                    stops: const [0.3, 1.0],
                  ),
                ),
              ),
              
              // Content
              Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Top row - Icon and check
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Category icon
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            template.icon,
                            style: const TextStyle(fontSize: 16),
                          ),
                        ),
                        // Selection indicator
                        if (isSelected)
                          Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              LucideIcons.check,
                              size: 14,
                              color: category.color,
                            ),
                          ),
                      ],
                    ),
                    
                    const Spacer(),
                    
                    // Title
                    Text(
                      template.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    
                    // Tags
                    if (template.tags.isNotEmpty)
                      Wrap(
                        spacing: 4,
                        children: template.tags.take(2).map((tag) {
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              tag,
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.9),
                                fontSize: 9,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Build gradient background for template card
  Widget _buildTemplateGradient(Color baseColor) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            baseColor.withOpacity(0.8),
            baseColor.withOpacity(0.4),
            Colors.black.withOpacity(0.6),
          ],
          stops: const [0.0, 0.5, 1.0],
        ),
      ),
    );
  }

  // -------- Image Upload --------
  Widget _buildImageUpload(String ref) {
    final input = _effectiveInputConfig(ref);
    final hasImage = _inputs[ref] != null && 
        (_inputs[ref] is List && (_inputs[ref] as List).isNotEmpty);

    return _buildCard(
      elevated: hasImage,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Image preview with elegant border
          _buildImagePreview(ref),
          const SizedBox(height: 16),

          // Upload button (full width)
          _buildActionButton(
            icon: hasImage ? LucideIcons.imagePlus : LucideIcons.upload,
            label: hasImage ? "Change Image" : "Upload Image",
            onPressed: () => _pickImage(input),
            isPrimary: true,
          ),
        ],
      ),
    );
  }

  // Reusable action button - uses consistent button variants
  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    bool isPrimary = false,
  }) {
    if (isPrimary) {
      return GradientButton(
        icon: icon,
        label: label,
        onPressed: onPressed,
        variant: ButtonVariant.primary,
        size: ButtonSize.medium,
        expanded: true,
      );
    }
    
    return GradientButton(
      icon: icon,
      label: label,
      onPressed: onPressed,
      variant: ButtonVariant.secondary,
      size: ButtonSize.medium,
      expanded: true,
    );
  }

  Widget _buildImagePreview(String ref) {
    final cs = Theme.of(context).colorScheme;
    final data = _inputs[ref];

    // Show loading state while processing
    if (_isProcessingImage) {
      return Container(
        height: 220,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              cs.surfaceContainerHigh.withOpacity(0.8),
              cs.surfaceContainerHighest.withOpacity(0.4),
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: cs.primary.withOpacity(0.3),
            width: 1.5,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 48,
              height: 48,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: cs.primary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              "Processing image...",
              style: TextStyle(
                color: cs.primary,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }

    if (data == null || (data is List && data.isEmpty)) {
      return Container(
        height: 220,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              cs.surfaceContainerHigh.withOpacity(0.8),
              cs.surfaceContainerHighest.withOpacity(0.4),
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: cs.outlineVariant.withOpacity(0.2),
            width: 1.5,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: cs.primary.withOpacity(0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(
                LucideIcons.imagePlus,
                color: cs.primary.withOpacity(0.6),
                size: 40,
              ),
            ),
            const SizedBox(height: 16),
              Text(
              "Tap to upload an image",
              style: TextStyle(
                color: cs.onSurfaceVariant.withOpacity(0.7),
                fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
              "Supports PNG, JPG, WEBP",
              style: TextStyle(
                color: cs.onSurfaceVariant.withOpacity(0.5),
                fontSize: 12,
                ),
              ),
          ],
        ),
      );
    }

    // unwrap
    final list =
        (data is List) ? List<Uint8List>.from(data) : [data as Uint8List];
    final mask = _inputs["mask_image"];

    final bool isOutpaint = widget.config.model == "diffusers_outpaint";

    // read alignment & aspect ratio (from OutpaintCanvasPage)
    final String alignment =
        isOutpaint ? (_inputs["alignment"] ?? "Middle") : "Middle";
    final String ratioStr =
        isOutpaint ? (_inputs["aspect_ratio"] ?? "1:1") : "1:1";

    final ratioParts = ratioStr.split(":");
    final double aspectRatio = (ratioParts.length == 2)
        ? (double.tryParse(ratioParts[0]) ?? 1) /
            (double.tryParse(ratioParts[1]) ?? 1)
        : 1.0;

    // Simple padding logic — show empty area on the expansion side
    EdgeInsets imgPadding = EdgeInsets.zero;
    if (isOutpaint) {
      switch (alignment) {
        case "Left":
          imgPadding = const EdgeInsets.only(right: 60); // expand right
          break;
        case "Right":
          imgPadding = const EdgeInsets.only(left: 60); // expand left
          break;
        case "Top":
          imgPadding = const EdgeInsets.only(bottom: 60); // expand down
          break;
        case "All Sides":
          imgPadding = const EdgeInsets.all(60);
          break;
        case "Bottom":
          imgPadding = const EdgeInsets.only(top: 60); // expand up
          break;
        default:
          imgPadding = EdgeInsets.zero;
      }
    }

    // Check if this is a multi-image input
    final input = _effectiveInputConfig(ref);
    final maxImages = input["max"] ?? 1;
    final isMultiImage = maxImages > 1 && list.length > 1;

    // For multi-image inputs, show a grid of thumbnails
    if (isMultiImage) {
      return Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: cs.primary.withOpacity(0.3),
            width: 2,
          ),
          color: cs.surfaceContainerHigh,
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with count
            Row(
              children: [
                Icon(LucideIcons.galleryVertical, size: 18, color: cs.primary),
                const SizedBox(width: 8),
                Text(
                  '${list.length} images selected',
                  style: TextStyle(
                    color: cs.onSurface,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(LucideIcons.check, size: 12, color: Colors.green.shade600),
                      const SizedBox(width: 4),
                      Text(
                        'Ready',
                        style: TextStyle(
                          color: Colors.green.shade600,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Image grid
            SizedBox(
              height: 100,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: list.length,
                itemBuilder: (context, index) {
                  return Padding(
                    padding: EdgeInsets.only(right: index < list.length - 1 ? 10 : 0),
                    child: Stack(
                      children: [
                        Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: cs.primary.withOpacity(0.3),
                              width: 1.5,
                            ),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(11),
                            child: Image.memory(
                              list[index],
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                        // Image number badge
                        Positioned(
                          left: 6,
                          top: 6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.6),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '${index + 1}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      );
    }

    // Single image preview (original behavior)
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: cs.primary.withOpacity(0.3),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: cs.primary.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: AspectRatio(
          aspectRatio: aspectRatio.clamp(0.5, 2.0),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Checker background only for outpaint
              if (isOutpaint)
                const CustomPaint(painter: _CheckerPainter())
              else
                Container(color: cs.surfaceContainerHigh),

              // Base image
              Padding(
                padding: imgPadding,
                child: Image.memory(
                  list.first,
                  fit: BoxFit.contain,
                  alignment: _convertAlignment(alignment),
                  width: double.infinity,
                  height: double.infinity,
                ),
              ),

              // Mask overlay (other models)
              if (mask != null)
                Positioned.fill(
                  child: Opacity(
                    opacity: 0.6,
                    child: Image.memory(mask as Uint8List, fit: BoxFit.contain),
                  ),
                ),
              
              // Image loaded indicator
              Positioned(
                right: 8,
                top: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        LucideIcons.check,
                        size: 14,
                        color: Colors.green.shade300,
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        "Image ready",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Alignment _convertAlignment(String a) {
    switch (a) {
      case "Left":
        return Alignment.centerLeft;
      case "Right":
        return Alignment.centerRight;
      case "Top":
        return Alignment.topCenter;
      case "Bottom":
        return Alignment.bottomCenter;
      case "All Sides":
        return Alignment.center;
      default:
        return Alignment.center;
    }
  }

  // -------- Slider --------
  Widget _buildSlider(String ref) {
    final cs = Theme.of(context).colorScheme;
    final input = widget.config.inputs
        .firstWhere((i) => i["id"] == ref, orElse: () => {});
    final label = input["label"] ?? ref;
    _inputs[ref] ??= input["default"] ?? input["min"] ?? 1.0;
    final minVal = (input["min"] as num?)?.toDouble() ?? 0;
    final maxVal = (input["max"] as num?)?.toDouble() ?? 100;
    final currentVal = (_inputs[ref] as num).toDouble();
    
    return _buildCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: cs.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  LucideIcons.sliders,
                    size: 18,
                    color: cs.primary,
                  ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                    label,
                  style: TextStyle(
                      color: cs.onSurface,
                    fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: cs.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  currentVal.toStringAsFixed(currentVal % 1 == 0 ? 0 : 1),
                  style: TextStyle(
                    color: cs.primary,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: cs.primary,
              inactiveTrackColor: cs.outlineVariant.withOpacity(0.3),
              thumbColor: cs.primary,
              overlayColor: cs.primary.withOpacity(0.15),
              trackHeight: 6,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 20),
            ),
            child: Slider(
              value: currentVal.clamp(minVal, maxVal),
              min: minVal,
              max: maxVal,
              divisions: ((maxVal - minVal) * 10).round().clamp(1, 100),
              onChanged: (v) => setState(() => _inputs[ref] = v),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                  minVal.toStringAsFixed(minVal % 1 == 0 ? 0 : 1),
                  style: TextStyle(
                  color: cs.onSurfaceVariant.withOpacity(0.6),
                    fontSize: 12,
                ),
              ),
              Text(
                  maxVal.toStringAsFixed(maxVal % 1 == 0 ? 0 : 1),
                  style: TextStyle(
                  color: cs.onSurfaceVariant.withOpacity(0.6),
                    fontSize: 12,
                ),
              ),
            ],
            ),
          ),
        ],
      ),
    );
  }

  // -------- Dropdown (ChoiceChips) --------
  Widget _buildDropdown(String ref) {
    final cs = Theme.of(context).colorScheme;
    final input = widget.config.inputs
        .firstWhere((i) => i["id"] == ref, orElse: () => {});
    final label = input["label"] ?? ref;
    final options = List<String>.from(input["options"] ?? []);
    _inputs[ref] ??= options.isNotEmpty ? options.first : null;

    return _buildCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: cs.secondary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                LucideIcons.list,
                size: 18,
                  color: cs.secondary,
              ),
              ),
              const SizedBox(width: 12),
              Text(
                label,
                style: TextStyle(
                  color: cs.onSurface,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: options.map((opt) {
                  final isSelected = _inputs[ref] == opt;
              return Material(
                color: isSelected
                    ? cs.primary
                    : cs.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                    onTap: () => setState(() => _inputs[ref] = opt),
                    borderRadius: BorderRadius.circular(12),
                  child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected
                            ? cs.primary
                            : cs.outlineVariant.withOpacity(0.3),
                      ),
                      boxShadow: isSelected
                          ? [
                              BoxShadow(
                                color: cs.primary.withOpacity(0.25),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ]
                          : null,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isSelected) ...[
                          Icon(
                            LucideIcons.check,
                            size: 16,
                            color: cs.onPrimary,
                      ),
                          const SizedBox(width: 6),
                        ],
                        Text(
                        opt,
                          style: TextStyle(
                          color: isSelected
                                ? cs.onPrimary
                              : cs.onSurfaceVariant,
                            fontWeight:
                                isSelected ? FontWeight.w600 : FontWeight.w500,
                            fontSize: 14,
                          ),
                        ),
                      ],
                        ),
                      ),
                    ),
                  );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildPainter(String ref) {
    final cs = Theme.of(context).colorScheme;

    // Find the image input for mask base
    Map<String, dynamic>? baseImageInput;
    for (final i in widget.config.inputs) {
      if (i["type"] == "image" && i["id"] != ref) {
        baseImageInput = i;
        break;
      }
    }

    final raw = baseImageInput != null ? _inputs[baseImageInput["id"]] : null;

    Uint8List? baseBytes;
    if (raw is List && raw.isNotEmpty) {
      baseBytes = raw.first as Uint8List;
    } else if (raw is Uint8List) {
      baseBytes = raw;
    }

    final hasMask = _inputs["mask_image"] != null;

    // Hide button entirely until image is selected
    if (baseBytes == null && !hasMask) {
      return const SizedBox.shrink();
    }

    return _buildCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: hasMask
                      ? Colors.green.withOpacity(0.12)
                      : cs.tertiary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  hasMask ? LucideIcons.checkCircle : LucideIcons.paintbrush,
                size: 18,
                  color: hasMask ? Colors.green : cs.tertiary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
              Text(
                      "Mask Region",
                      style: TextStyle(
                      color: cs.onSurface,
                        fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
              ),
                    const SizedBox(height: 2),
                    Text(
                      hasMask
                          ? "Mask created - tap to edit"
                          : "Draw over areas to modify",
                      style: TextStyle(
                        color: cs.onSurfaceVariant.withOpacity(0.7),
                        fontSize: 12,
                    ),
              ),
            ],
          ),
              ),
              Material(
                color: hasMask
                    ? cs.surfaceContainerHigh
                    : cs.tertiary,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  onTap: () async {
              final base = baseBytes ?? (_inputs["init_image"]?[0] as Uint8List?);
              if (base != null) {
                final mask = await _openMaskEditor(base);
                if (mask != null) {
                  setState(() {
                    _inputs["mask_image"] = mask;
                  });
                }
              }
            },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          hasMask ? LucideIcons.edit3 : LucideIcons.paintbrush,
                          size: 18,
                          color: hasMask ? cs.onSurfaceVariant : Colors.white,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          hasMask ? "Edit" : "Draw Mask",
                          style: TextStyle(
                            color: hasMask ? cs.onSurfaceVariant : Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          
          // Show mask preview if available
          if (hasMask) ...[
            const SizedBox(height: 12),
            Container(
              height: 80,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.green.withOpacity(0.3),
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(11),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (baseBytes != null)
                      Image.memory(
                        baseBytes,
                        fit: BoxFit.cover,
                      ),
                    Container(
                      color: Colors.black.withOpacity(0.3),
                    ),
                    ColorFiltered(
                      colorFilter: const ColorFilter.mode(
                        Colors.red,
                        BlendMode.srcATop,
                      ),
                      child: Opacity(
                        opacity: 0.5,
                        child: Image.memory(
                          _inputs["mask_image"] as Uint8List,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    Positioned(
                      right: 8,
                      bottom: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              LucideIcons.check,
                              size: 12,
                              color: Colors.white,
                            ),
                            SizedBox(width: 4),
                            Text(
                              "Mask applied",
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDynamicInputScreen() {
    final cs = Theme.of(context).colorScheme;
    // Get safe area padding for devices with home bar/navigation buttons
    final bottomSafeArea = MediaQuery.of(context).padding.bottom;
    
    // Filter out generate_button from elements (will be rendered in sticky footer)
    final contentElements = _currentElements
        .where((e) => e["type"] != "generate_button")
        .toList();
    
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            cs.surface,
            cs.surfaceContainerLowest,
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Column(
        children: [
          // Scrollable content area
          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.only(
                left: 16,
                right: 16,
                top: 8,
                bottom: 8,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Mode selector (if applicable)
                  if (widget.config.modes != null && widget.config.modes!.isNotEmpty) ...[
                    _buildModeSelector(),
                    const SizedBox(height: 4),
                  ],
                  
                  // Dynamic elements (without generate button)
                  ...contentElements.map((e) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: _buildElement(e),
                    );
                  }),
                ],
              ),
            ),
          ),
          
          // Sticky bottom area with settings + generate button
          _buildStickyGenerateFooter(bottomSafeArea),
        ],
      ),
    );
  }

  /// Build the sticky footer with settings and generate button
  Widget _buildStickyGenerateFooter(double bottomSafeArea) {
    final cs = Theme.of(context).colorScheme;
    final isEnabled = _areRequiredInputsFilled();
    final missingInputs = _getMissingInputs();
    
    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 12,
        bottom: 12 + bottomSafeArea,
      ),
      decoration: BoxDecoration(
        color: cs.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 10,
            offset: const Offset(0, -4),
          ),
        ],
        border: Border(
          top: BorderSide(
            color: cs.outlineVariant.withOpacity(0.1),
            width: 1,
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Missing inputs hint (shown when button is disabled)
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            child: !isEnabled && missingInputs.isNotEmpty
                ? Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: _isProcessingImage 
                          ? cs.primaryContainer.withOpacity(0.3)
                          : cs.errorContainer.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: _isProcessingImage
                            ? cs.primary.withOpacity(0.2)
                            : cs.error.withOpacity(0.2),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_isProcessingImage)
                          SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: cs.primary.withOpacity(0.8),
                            ),
                          )
                        else
                          Icon(
                            LucideIcons.alertCircle,
                            size: 14,
                            color: cs.error.withOpacity(0.8),
                          ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            _isProcessingImage 
                                ? "Processing image..."
                                : "Add ${missingInputs.join(' & ')} to continue",
                            style: TextStyle(
                              color: _isProcessingImage
                                  ? cs.primary.withOpacity(0.9)
                                  : cs.error.withOpacity(0.9),
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          
          // Settings button + Generate button row
          Row(
            children: [
              // Settings button
              InkWell(
                onTap: _showAdvancedSettings,
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: cs.outlineVariant.withOpacity(0.3),
                    ),
                  ),
                  child: Icon(
                    LucideIcons.settings,
                    size: 22,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              
              // Generate button with glow
              Expanded(
                child: _buildAnimatedGenerateButton(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Build the animated generate button with glow effect
  Widget _buildAnimatedGenerateButton() {
    final cs = Theme.of(context).colorScheme;
    final offer = _currentModelOffer;
    final variations = _advancedSettings.variations;
    
    // Check if upscale is enabled
    final bool isUpscaled = _advancedSettings.upscaleOutput && _scaleFactor > 1;

    // Use the unified cost calculation that includes variations
    final totalCost = _calculateTotalCost();
    
    // Calculate cost before discount (for showing strikethrough if offer)
    final baseCostPerVariation = _currentModelCost + (isUpscaled ? _currentModelUpscaleCost : 0);
    final totalBeforeDiscount = baseCostPerVariation * variations;

    // Check if button should be enabled
    final isEnabled = _areRequiredInputsFilled();

    return AnimatedBuilder(
      animation: _glowAnimationController,
      builder: (context, child) {
        final glowOpacity = isEnabled 
            ? 0.3 + (_glowAnimationController.value * 0.2) 
            : 0.0;
        
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: isEnabled
                ? [
                    BoxShadow(
                      color: KalaColors.purple.withOpacity(glowOpacity),
                      blurRadius: 16 + (_glowAnimationController.value * 8),
                      offset: const Offset(0, 4),
                    ),
                    BoxShadow(
                      color: KalaColors.cyan.withOpacity(glowOpacity * 0.6),
                      blurRadius: 20 + (_glowAnimationController.value * 10),
                      offset: const Offset(0, 6),
                    ),
                  ]
                : null,
          ),
          child: Opacity(
            opacity: isEnabled ? 1.0 : 0.6,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: LinearGradient(
                  colors: isEnabled
                      ? KalaColors.brandGradient
                      : [cs.onSurfaceVariant.withOpacity(0.4), cs.onSurfaceVariant.withOpacity(0.3)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: isEnabled ? _handleGenerateTap : null,
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Sparkles icon
                        const Icon(
                          LucideIcons.sparkles,
                          color: Colors.white,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        // Generate text
                        const Text(
                          "Generate",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.3,
                          ),
                        ),
                        
                        // Divider
                        Container(
                          margin: const EdgeInsets.symmetric(horizontal: 12),
                          height: 20,
                          width: 1,
                          color: Colors.white.withOpacity(0.3),
                        ),
                        
                        // Variations badge (show if > 1)
                        if (variations > 1) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.2),
                                width: 1,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  LucideIcons.layers,
                                  size: 13,
                                  color: Colors.white.withOpacity(0.9),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  "$variations",
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                        
                        // Cost display
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                LucideIcons.gem,
                                size: 14,
                                color: Colors.white.withOpacity(0.9),
                              ),
                              const SizedBox(width: 4),
                              if (offer > 0 && totalBeforeDiscount != totalCost) ...[
                                Text(
                                  "$totalBeforeDiscount",
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.6),
                                    fontSize: 12,
                                    decoration: TextDecoration.lineThrough,
                                    decorationColor: Colors.white.withOpacity(0.6),
                                  ),
                                ),
                                const SizedBox(width: 3),
                              ],
                              Text(
                                "$totalCost",
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Handle generate tap with haptic feedback
  void _handleGenerateTap() {
    // Trigger haptic feedback
    HapticFeedback.mediumImpact();
    // Call the actual job runner
    _runJob();
  }

  Widget _buildModeSelector() {
    final cs = Theme.of(context).colorScheme;
    final modes = widget.config.modes!;
    final modeKeys = modes.keys.toList();

    return _buildCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: cs.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                LucideIcons.layers,
                size: 18,
                color: cs.primary,
              ),
              ),
              const SizedBox(width: 12),
              Text(
                "Mode",
                style: TextStyle(
                  color: cs.onSurface,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Mode pills
          Container(
            decoration: BoxDecoration(
              color: cs.surfaceContainerHigh.withOpacity(0.6),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: cs.outlineVariant.withOpacity(0.2)),
            ),
            padding: const EdgeInsets.all(4),
            child: Row(
              children: modeKeys.map((key) {
                final selected = _selectedModeKey == key;
                final label = modes[key]?["label"] ?? key;
                
                return Expanded(
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedModeKey = key;
                        _promptController.clear();
                      });
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOutCubic,
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                      decoration: BoxDecoration(
                        gradient: selected
                            ? const LinearGradient(
                                colors: KalaColors.brandGradient,
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              )
                            : null,
                        borderRadius: BorderRadius.circular(11),
                        boxShadow: selected
                            ? [
                                BoxShadow(
                                  color: KalaColors.purple.withOpacity(0.35),
                                  blurRadius: 10,
                                  offset: const Offset(0, 3),
                                ),
                              ]
                            : [],
                      ),
                      child: Center(
                        child: Text(
                          label,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: selected
                                ? cs.onPrimary
                                : cs.onSurfaceVariant,
                            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------
  // 💎 INSUFFICIENT CREDITS SHEET
  // ----------------------------------------------------

  void _showInsufficientCreditsSheet({
    required int requiredCredits,
    required int currentCredits,
  }) {
    final cs = Theme.of(context).colorScheme;
    final shortage = requiredCredits - currentCredits;

    showModalBottomSheet(
      context: context,
      backgroundColor: cs.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icon
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  LucideIcons.gem,
                  size: 40,
                  color: Colors.orange.shade600,
                ),
              ),
              const SizedBox(height: 16),

              // Title
              Text(
                'Insufficient Credits',
                style: TextStyle(
                  color: cs.onSurface,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),

              // Details
              Text(
                'You need $requiredCredits credits for this action',
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),

              // Credit comparison
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Flexible(
                      child: _buildCreditInfo(
                        cs,
                        label: 'You have',
                        value: currentCredits.toString(),
                        color: cs.primary,
                      ),
                    ),
                    Container(
                      width: 1,
                      height: 40,
                      color: cs.outlineVariant,
                    ),
                    Flexible(
                      child: _buildCreditInfo(
                        cs,
                        label: 'Need',
                        value: '+$shortage',
                        color: Colors.orange.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Get Credits Button
              SizedBox(
                width: double.infinity,
                child: GradientButton(
                  label: 'Get Credits',
                  icon: LucideIcons.gem,
                  onPressed: () {
                    Navigator.pop(context); // Close bottom sheet
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const CreditsPage()),
                    );
                  },
                  variant: ButtonVariant.primary,
                  size: ButtonSize.large,
                  expanded: true,
                ),
              ),
              const SizedBox(height: 8),

              // Cancel button
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  'Cancel',
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCreditInfo(
    ColorScheme cs, {
    required String label,
    required String value,
    required Color color,
  }) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            color: cs.onSurfaceVariant,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.gem, size: 16, color: color),
            const SizedBox(width: 4),
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ----------------------------------------------------
  // 🛰️ JOB SUBMISSION + POLLING
  // ----------------------------------------------------

  // Track if a job submission is in progress to prevent double execution
  bool _isSubmittingJob = false;

  Future<void> _runJob() async {
    // Prevent double execution from rapid taps
    if (_isSubmittingJob) {
      debugPrint("⚠️ Job submission already in progress, ignoring tap");
      return;
    }
    _isSubmittingJob = true;

    final cs = Theme.of(context).colorScheme;

    // --- Check if user is signed in ---
    if (!AuthService().isSignedIn) {
      final signedIn = await requireSignIn(context, feature: 'AI Tools');
      if (!signedIn) {
        _isSubmittingJob = false;
        return;
      }
    }

    // --- Check credits ---
    final totalCost = _calculateTotalCost();
    final currentCredits = userCreditsNotifier.value;
    if (!UserService().hasEnoughCredits(totalCost)) {
      _isSubmittingJob = false;
      if (mounted) {
        _showInsufficientCreditsSheet(
          requiredCredits: totalCost,
          currentCredits: currentCredits,
        );
      }
      return;
    }

    // --- Ensure all live UI values are captured ---
    if (_hasPrompt) {
      _inputs["prompt"] = _promptController.text.trim();
    }
    if (_hasScaleFactor || _inputs.containsKey("scale_factor")) {
      _inputs["scale_factor"] = _upscaleEnabled ? _scaleFactor : 1;
    }

    // --- Show progress dialog ---
    final ValueNotifier<String> dialogMessage = ValueNotifier<String>(
      "Hang tight while we queue and process your request.\nAvoid pressing back or closing the app.",
    );
    Timer? messageTimer;
    messageTimer = Timer(const Duration(seconds: 45), () {
      dialogMessage.value =
          "Still working... It's taking a bit longer than usual.\nPlease stay on this screen.";
    });

    // Track dialog visibility for safe dismissal
    bool dialogShowing = false;
    
    // Helper to safely dismiss the dialog
    void dismissDialog() {
      messageTimer?.cancel();
      if (dialogShowing && mounted) {
        dialogShowing = false;
        Navigator.of(context, rootNavigator: true).pop();
      }
    }

    if (!mounted) {
      _isSubmittingJob = false;
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        dialogShowing = true;
        return Dialog(
          backgroundColor: cs.surface,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          insetPadding: const EdgeInsets.symmetric(horizontal: 40),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: cs.outlineVariant.withOpacity(0.2),
              ),
              boxShadow: [
                BoxShadow(
                  color: cs.primary.withOpacity(0.08),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Animated progress indicator with glow
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: cs.primary.withOpacity(0.08),
                    shape: BoxShape.circle,
                  ),
                  child: SizedBox(
                    width: 40,
                    height: 40,
                    child: CircularProgressIndicator(
                      strokeWidth: 3.5,
                      color: cs.primary,
                      strokeCap: StrokeCap.round,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                
                // Title with icon
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      LucideIcons.sparkles,
                      size: 20,
                      color: cs.primary,
                    ),
                    const SizedBox(width: 10),
                Text(
                      "Creating Magic",
                  style: TextStyle(
                    color: cs.onSurface,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                  ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                
                // Description
                ValueListenableBuilder<String>(
                  valueListenable: dialogMessage,
                  builder: (_, value, __) => Text(
                    value,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: cs.onSurfaceVariant.withOpacity(0.8),
                      fontSize: 14,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    const int maxRetries = 3;
    int attempt = 0;

    while (attempt < maxRetries) {
      attempt++;
      try {
        // --- Clone _inputs for encoding ---
        final encoded = Map<String, dynamic>.from(_inputs);

        // 🩵 Ensure prompt is included even if empty in _inputs
        if (_hasPrompt &&
            (encoded["prompt"] == null ||
                (encoded["prompt"] is String &&
                    (encoded["prompt"] as String).isEmpty))) {
          encoded["prompt"] = _promptController.text.trim();
        }

        // 🩵 Auto-inject mode for multi-mode tools (WAN / SDXL)
        if (widget.config.params?.containsKey("mode") == true &&
            _selectedModeKey != null &&
            !_inputs.containsKey("mode")) {
          encoded["mode"] = _selectedModeKey;
          debugPrint("🧩 Injected mode: $_selectedModeKey");
        }

        // 🩵 Fallback: make sure root_params prompt is filled
        if (widget.config.rootParams != null &&
            !widget.config.rootParams!.containsKey("prompt")) {
          widget.config.rootParams!["prompt"] = "{{prompt}}";
        }

        // Helper to ensure clean base64 encoding with proper padding
        String encodeToCleanBase64(Uint8List bytes) {
          // Encode to base64 (standard RFC 4648)
          // Dart's base64Encode always produces correctly padded base64
          String b64 = base64Encode(bytes);
          
          // Remove any whitespace (shouldn't be there, but just in case)
          b64 = b64.replaceAll(RegExp(r'\s+'), '');
          
          // Validate: length should be multiple of 4
          final len = b64.length;
          final mod4 = len % 4;
          
          // If not multiple of 4, fix padding
          if (mod4 != 0) {
            // Strip existing = and recalculate
            final stripped = b64.replaceAll('=', '');
            final strippedMod4 = stripped.length % 4;
            if (strippedMod4 == 0) {
              b64 = stripped; // No padding needed
            } else {
              b64 = stripped + ('=' * (4 - strippedMod4));
            }
            debugPrint('⚠️ Fixed base64 padding: $len → ${b64.length} chars');
          }
          
          // Final validation
          final isValid = RegExp(r'^[A-Za-z0-9+/]+={0,2}$').hasMatch(b64);
          final ends = b64.length > 12 ? b64.substring(b64.length - 12) : b64;
          
          debugPrint('📦 Base64: ${bytes.length} bytes → ${b64.length} chars, mod4=${b64.length % 4}, valid=$isValid, ends: $ends');
          
          if (!isValid) {
            debugPrint('⚠️ Invalid base64! First 50 chars: ${b64.substring(0, min(50, b64.length))}');
          }
          
          return b64;
        }

        // Encode Uint8List images → base64
        for (final key in encoded.keys.toList()) {
          final val = encoded[key];
          if (val is Uint8List) {
            encoded[key] = encodeToCleanBase64(val);
          } else if (val is List) {
            if (val.isEmpty) {
              encoded.remove(key);
              continue;
            }
            if (val.first is Uint8List) {
              encoded[key] = val.length == 1
                  ? encodeToCleanBase64(val.first as Uint8List)
                  : val.map((e) => encodeToCleanBase64(e as Uint8List)).toList();
            } else {
              encoded[key] = val.length == 1 ? val.first : val;
            }
          }
        }

        // 🩵 Safe default for sliders (avoid missing scale_factor)
        if (!encoded.containsKey("scale_factor")) {
          final def = widget.config.inputs.firstWhere(
              (i) => i["id"] == "scale_factor",
              orElse: () => {"default": 1});
          encoded["scale_factor"] = def["default"] ?? 1;
        }

        // --- Auto width/height inference (with null safety) ---
        try {
          final imgInput = widget.config.inputs
              .firstWhere((i) => i["type"] == "image", orElse: () => {});
          final id = imgInput["id"];
          if (encoded.containsKey(id)) {
            final imgVal = encoded[id];
            Uint8List? firstImg;
            if (imgVal is String) {
              if (imgVal.isNotEmpty) firstImg = base64Decode(imgVal);
            } else if (imgVal is List &&
                imgVal.isNotEmpty &&
                imgVal.first is String) {
              final s = imgVal.first as String;
              if (s.isNotEmpty) firstImg = base64Decode(s);
            }

            if (firstImg != null && firstImg.isNotEmpty) {
              final codec = await ui.instantiateImageCodec(firstImg);
              final frame = await codec.getNextFrame();
              final img = frame.image;
              int roundTo32(int x) => ((x / 32).round() * 32).clamp(32, 2048);
              encoded["width"] = roundTo32(img.width);
              encoded["height"] = roundTo32(img.height);
              img.dispose();
            }
          }
        } catch (_) {}

        // --- Build params dynamically ---
        final Map<String, dynamic> resolvedParams = {};
        final Set<String> consumedInputs = {};

        dynamic getInputValue(String refId) {
          if (encoded.containsKey(refId)) return encoded[refId];

          // Support model-specific input overrides (e.g. qwen_image_edit_2509 references {{images}}
          // but the base input id is init_image).
          try {
            final overrides = _selectedModelData?['inputOverrides'] as Map<String, dynamic>?;
            if (overrides != null && overrides.isNotEmpty) {
              for (final entry in overrides.entries) {
                final baseId = entry.key;
                final o = entry.value;
                if (o is Map && o['id'] is String) {
                  final overrideId = o['id'] as String;

                  // If template asks for overrideId (e.g. "images"), return the base value ("init_image").
                  if (overrideId == refId ||
                      overrideId.replaceAll('-', '_') == refId.replaceAll('-', '_')) {
                    if (encoded.containsKey(baseId)) return encoded[baseId];
                  }

                  // If template asks for baseId, return overrideId value (in case UI stored it there).
                  if (baseId == refId ||
                      baseId.replaceAll('-', '_') == refId.replaceAll('-', '_')) {
                    if (encoded.containsKey(overrideId)) return encoded[overrideId];
                  }
                }
              }
            }
          } catch (_) {}

          final aliases = [
            refId,
            refId.replaceAll('-', '_'),
            refId.replaceAll('_factor', ''),
            '${refId}_factor',
          ];
          for (final alias in aliases) {
            if (encoded.containsKey(alias)) return encoded[alias];
          }
          try {
            final def = widget.config.inputs.firstWhere(
              (i) =>
                  i is Map &&
                  (i['id'] == refId || i['id'] == refId.replaceAll('-', '_')),
              orElse: () => null,
            );
            if (def != null && def is Map && def.containsKey('default')) {
              return def['default'];
            }
          } catch (_) {}
          return null;
        }

        // Get params from selected model or fallback to config
        final Map<String, dynamic>? modelParams = 
            _selectedModelData?['params'] as Map<String, dynamic>? ?? 
            widget.config.params;
        final Map<String, dynamic>? modelRootParams = 
            _selectedModelData?['rootParams'] as Map<String, dynamic>? ?? 
            widget.config.rootParams;

        // Resolve {{template}} placeholders
        modelParams?.forEach((key, value) {
          dynamic val = value;
          if (val is String) {
            final reg = RegExp(r"\{\{([\w\-]+)\}\}");
            for (final m in reg.allMatches(val)) {
              final ref = m.group(1)!;
              final fetched = getInputValue(ref);
              if (fetched != null) {
                val = fetched;
                consumedInputs.add(ref);
              } else {
                debugPrint('⚠️ Unresolved param placeholder {{$ref}} for key="$key" (model=${_selectedModelId ?? widget.config.model})');
              }
            }
          }
          resolvedParams[key] = val;
        });

        // --- Root params ---
        final Map<String, dynamic> rootParams = {};
        modelRootParams?.forEach((key, value) {
          dynamic val = value;
          if (val is String && val.startsWith("{{") && val.endsWith("}}")) {
            final refId = val.substring(2, val.length - 2);
            final fetched = getInputValue(refId);
            if (fetched != null) {
              val = fetched;
              consumedInputs.add(refId);
            } else {
              debugPrint('⚠️ Unresolved root placeholder {{$refId}} for key="$key" (model=${_selectedModelId ?? widget.config.model})');
            }
          }
          rootParams[key] = val;
        });

        // ✅ Ensure root prompt present even if not resolved
        if (!rootParams.containsKey("prompt") &&
            encoded.containsKey("prompt")) {
          rootParams["prompt"] = encoded["prompt"];
        }

        // --- FCM token ---
        final prefs = await SharedPreferences.getInstance();
        String? fcmToken = prefs.getString("fcm_token");
        if (fcmToken == null) {
          fcmToken = await FirebaseMessaging.instance.getToken();
          if (fcmToken != null) await prefs.setString("fcm_token", fcmToken);
        }

        // --- Apply advanced settings to params ---
        // CFG Scale
        resolvedParams["cfg_scale"] = _advancedSettings.cfgScale;
        
        // Scale factor from upscale settings (1 = off, 2 or 4 = on)
        // scale_image is always true, only scale_factor changes
        resolvedParams["scale_factor"] = _advancedSettings.upscaleOutput ? _scaleFactor : 1;
        resolvedParams["scale_image"] = true;
        
        // Calculate height/width based on aspect ratio selection
        // If "Default" - use image's original dimensions (already set from image inference above)
        // Otherwise - calculate based on selected aspect ratio
        if (_advancedSettings.aspectRatio != 'Default') {
          final selectedRatio = _advancedSettings.aspectRatio;
          final ratioParts = selectedRatio.split(':');
          if (ratioParts.length == 2) {
            final ratioW = double.tryParse(ratioParts[0]) ?? 1;
            final ratioH = double.tryParse(ratioParts[1]) ?? 1;
            final targetRatio = ratioW / ratioH;
            
            // Get current dimensions (may have been inferred from image)
            final currentWidth = resolvedParams["width"] as int? ?? 896;
            final currentHeight = resolvedParams["height"] as int? ?? 896;
            
            // Calculate new dimensions maintaining the larger dimension
            int newWidth, newHeight;
            if (targetRatio >= 1.0) {
              // Landscape or square - base on width
              newWidth = currentWidth;
              newHeight = (currentWidth / targetRatio).round();
            } else {
              // Portrait - base on height
              newHeight = currentHeight;
              newWidth = (currentHeight * targetRatio).round();
            }
            
            // Round to nearest 32 (required by most models)
            int roundTo32(int x) => ((x / 32).round() * 32).clamp(32, 2048);
            resolvedParams["width"] = roundTo32(newWidth);
            resolvedParams["height"] = roundTo32(newHeight);
          }
        }

        // --- Build payload ---
        // IMPORTANT: To avoid GPU OOM with multi-variation batches, we submit
        // variations as SEPARATE jobs (variations=1 each) when user selects >1.
        //
        // This keeps worker behavior identical to "normal" (variations=1) jobs.
        final modelId = _selectedModelId ?? widget.config.model;
        final int requestedVariations =
            _advancedSettings.variations.clamp(1, 4);

        final basePayload = <String, dynamic>{
          "model": modelId,
          "params": resolvedParams,
          "fcm_token": fcmToken,
          // Root level settings (not in params)
          "enhance_prompt": _advancedSettings.enhancePrompt,
          // Always submit single-variation jobs; we loop for requestedVariations.
          "variations": 1,
          ...rootParams,
        };

        debugPrint("🎯 Using model: $modelId");
        debugPrint(
          "🔧 Advanced settings - enhance: ${_advancedSettings.enhancePrompt}, "
          "variations: $requestedVariations (submitted as $requestedVariations separate jobs), "
          "cfg: ${_advancedSettings.cfgScale}, aspect: ${_advancedSettings.aspectRatio}",
        );

        // --- Firebase Auth ---
        final firebaseToken = await _authService.getIdToken();
        if (firebaseToken == null) {
          throw Exception("Not authenticated. Please sign in first.");
        }

        final headers = {
          "Content-Type": "application/json",
          "Authorization": "Bearer $firebaseToken",
        };

        // Save input preview once (reused for all submitted jobs)
        String? inputImageLocalPath;
        try {
          final imageInput = widget.config.inputs
              .firstWhere((i) => i["type"] == "image", orElse: () => {});
          if (imageInput.isNotEmpty) {
            final id = imageInput["id"];
            final dat = _inputs[id];
            if (dat != null &&
                dat is List &&
                dat.isNotEmpty &&
                dat.first is Uint8List) {
              final tmpDir = await FileService.getTempDir();
              final thumbFile = File(
                  '${tmpDir.path}/thumb_${DateTime.now().millisecondsSinceEpoch}.jpg');
              await thumbFile.writeAsBytes(dat.first as Uint8List, flush: true);
              inputImageLocalPath = thumbFile.path;
            } else {
              final existingPath = _inputs["${id}_path"];
              if (existingPath != null && File(existingPath).existsSync()) {
                inputImageLocalPath = existingPath;
              }
            }
          }
        } catch (e) {
          debugPrint("⚠️ Could not save stable input preview: $e");
        }

        final String? originalPrompt = _inputs["prompt"] as String?;
        final List<JobModel> createdJobs = [];

        for (int i = 0; i < requestedVariations; i++) {
          // Per-job retry loop to avoid duplicating already-submitted jobs.
          dynamic data;
          for (int submitAttempt = 1; submitAttempt <= maxRetries; submitAttempt++) {
            // Clone params per submit to avoid any accidental mutation and to guarantee
            // image inputs are always present (some backends accept `init_image` or `images`).
            final paramsForSubmit = Map<String, dynamic>.from(resolvedParams);
            if (paramsForSubmit["init_image"] is List) {
              paramsForSubmit["init_image"] = List<dynamic>.from(paramsForSubmit["init_image"] as List);
            }
            if (paramsForSubmit["images"] is List) {
              paramsForSubmit["images"] = List<dynamic>.from(paramsForSubmit["images"] as List);
            }

            // If one alias exists, mirror it to the other (worker checks both).
            if (!paramsForSubmit.containsKey("init_image") &&
                paramsForSubmit.containsKey("images")) {
              paramsForSubmit["init_image"] = paramsForSubmit["images"];
            }
            if (!paramsForSubmit.containsKey("images") &&
                paramsForSubmit.containsKey("init_image")) {
              paramsForSubmit["images"] = paramsForSubmit["init_image"];
            }

            final dynamic ii = paramsForSubmit["init_image"];
            final int iiCount = ii is List
                ? ii.length
                : (ii is String && ii.isNotEmpty ? 1 : 0);
            debugPrint(
              "🖼️ Submit ${i + 1}/$requestedVariations init_image_count=$iiCount type=${ii.runtimeType}",
            );

            debugPrint(
              "🚀 Submitting job ${i + 1}/$requestedVariations (attempt $submitAttempt/$maxRetries)",
            );
            final resp = await http
                .post(
                  Uri.parse('$controllerUrl/submit'),
                  headers: headers,
                  body: jsonEncode(<String, dynamic>{
                    ...basePayload,
                    "params": paramsForSubmit,
                  }),
                )
                .timeout(const Duration(seconds: 60));

            if (resp.statusCode == 200) {
              data = jsonDecode(resp.body);
              break;
            }

            debugPrint("❌ Submit ${i + 1}/$requestedVariations failed: ${resp.statusCode} ${resp.body}");
            if (submitAttempt < maxRetries) {
              await Future.delayed(const Duration(seconds: 2));
            }
          }

          if (data == null) {
            throw Exception("Failed to submit variation ${i + 1}/$requestedVariations after $maxRetries retries");
          }

          final jobId = data["job_id"];
          final downloadUrl = data["download_url"] ?? data["downloadUrl"];
          if (jobId == null) throw Exception("No job_id returned from submit");

          final bool promptWasEnhanced = data["prompt_enhanced"] ?? false;
          final String? enhancedPromptFromServer = data["enhanced_prompt"];

          final String title = await generateFriendlyJobName();
          final newJob = JobModel(
            jobId: jobId,
            title: title,
            model: widget.config.model,
            outputType: widget.config.outputType,
            downloadUrl: downloadUrl,
            status: 'processing',
            inputImagePath: inputImageLocalPath,
            // Each submitted job is a normal single-variation job.
            variations: 1,
            allCompleted: false,
            enhancedPrompt: enhancedPromptFromServer,
            promptEnhanced: promptWasEnhanced,
            originalPrompt: originalPrompt,
          );

          createdJobs.add(newJob);
          
          // ✅ Add job to notifier IMMEDIATELY so FCM handlers find it
          // This prevents ghost records from being created by FCM race conditions
          await addOrUpdateJob(newJob);

          final jobContext = {
            "title": widget.config.title,
            "model": widget.config.model,
            "inputs": widget.config.inputs,
            "params": widget.config.params,
            "outputType": widget.config.outputType,
          };
          await prefs.setString("notify_job_$jobId", jsonEncode(jobContext));

          // Small spacing to avoid back-to-back submits spiking memory/traffic.
          if (i < requestedVariations - 1) {
            await Future.delayed(const Duration(milliseconds: 250));
          }
        }
        
        // Jobs are already persisted via addOrUpdateJob - no need for redundant saves

        // Credits are deducted server-side during job processing
        await UserService().refreshCredits();

        dismissDialog();

        _isSubmittingJob = false;
        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ResultManagerPage()),
          );
        }

        debugPrint("✅ Submitted ${createdJobs.length}/$requestedVariations jobs successfully");
        return;
      } catch (e) {
        debugPrint("❌ Job submission attempt $attempt failed: $e");
        if (attempt >= maxRetries) {
          dismissDialog();
          _isSubmittingJob = false;
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                  content: Text(
                      "Error submitting job after $maxRetries retries: $e")),
            );
          }
          return;
        }
        await Future.delayed(const Duration(seconds: 2));
      }
    }
    // Safety reset in case loop exits without returning
    _isSubmittingJob = false;
  }

  // -------- Painter (Mask Editor) --------
  Future<Uint8List?> _openMaskEditor(Uint8List base) async {
    try {
      return await Navigator.push<Uint8List?>(
        context,
        MaterialPageRoute(
          builder: (_) => MaskEditorPage(
            baseImageBytes: base,
            existingMask: _inputs["mask_image"],
          ),
          fullscreenDialog: true,
        ),
      );
    } catch (e) {
      debugPrint("Mask editor failed: $e");
      return null;
    }
  }
}

// ---------------------------------------------------
// 🎨 Checker pattern background (used for Outpaint preview)
// ---------------------------------------------------
class _CheckerPainter extends CustomPainter {
  const _CheckerPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const double cell = 32;
    final paint1 = Paint()..color = const Color(0xFF2A2A2A);
    final paint2 = Paint()..color = const Color(0xFF1E1E1E);
    for (double y = 0; y < size.height; y += cell) {
      for (double x = 0; x < size.width; x += cell) {
        final usePaint = ((x / cell).floor() + (y / cell).floor()) % 2 == 0
            ? paint1
            : paint2;
        canvas.drawRect(Rect.fromLTWH(x, y, cell, cell), usePaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ------------------ MASK EDITOR ------------------
class MaskEditorPage extends StatefulWidget {
  final Uint8List baseImageBytes;
  final Uint8List? existingMask;

  const MaskEditorPage({
    super.key,
    required this.baseImageBytes,
    this.existingMask,
  });

  @override
  State<MaskEditorPage> createState() => _MaskEditorPageState();
}

class _MaskEditorPageState extends State<MaskEditorPage> {
  ui.Image? _image;
  bool _loading = true;
  ui.Image? _maskOverlay;

  // strokes: list of drawn strokes (in image pixel coordinates)
  final List<_Stroke> _strokes = [];
  _Stroke? _currentStroke;

  double _brushSize = 50.0;
  int? _lastImageHash;
  bool _eraser = false;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  int _hashBytes(Uint8List bytes) {
    int hash = 0;
    for (final b in bytes) {
      hash = (hash * 31 + b) & 0xFFFFFFFF;
    }
    return hash;
  }

  Future<void> _loadImage() async {
    try {
      final currentHash = _hashBytes(widget.baseImageBytes);
      final isNewImage =
          _lastImageHash == null || currentHash != _lastImageHash;
      _lastImageHash = currentHash;

      // Dispose old images to avoid GPU cache artifacts
      _image?.dispose();
      _maskOverlay?.dispose();

      // Always clear strokes for (re)open
      _strokes.clear();
      _currentStroke = null;
      _eraser = false;

      // If it's a NEW image, force-start fresh (ignore any existingMask)
      if (isNewImage) {
        _maskOverlay = null;
      } else {
        // Same image: load existingMask if provided
        _maskOverlay = null;
        if (widget.existingMask != null) {
          final maskCodec =
              await ui.instantiateImageCodec(widget.existingMask!);
          final maskFrame = await maskCodec.getNextFrame();
          _maskOverlay = maskFrame.image;
        }
      }

      // Decode the base image
      final codec = await ui.instantiateImageCodec(widget.baseImageBytes);
      final frame = await codec.getNextFrame();
      _image = frame.image;

      if (mounted) setState(() => _loading = false);
    } catch (e) {
      debugPrint("Failed to decode image in mask editor: $e");
      if (mounted) setState(() => _loading = false);
    }
  }

  // Convert local widget pos to image pixel coords
  Offset _toImageCoords(Offset localPos, Size displaySize) {
    final xInImageSpace = (localPos.dx / displaySize.width) * _image!.width;
    final yInImageSpace = (localPos.dy / displaySize.height) * _image!.height;
    return Offset(
      xInImageSpace.clamp(0.0, _image!.width.toDouble()),
      yInImageSpace.clamp(0.0, _image!.height.toDouble()),
    );
  }

  Future<Uint8List> _exportMask() async {
    final img = _image!;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final rect =
        Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble());

    canvas.saveLayer(rect, Paint());
    final paintSrc = Paint()..blendMode = BlendMode.src;

    if (_maskOverlay != null) {
      // draw existing mask at 1:1 (no scaling needed here)
      canvas.drawImage(_maskOverlay!, Offset.zero, paintSrc);
    }

    for (final s in _strokes) {
      if (s.points.length < 2) continue;

      final p = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = s.size // image-space size (you stored image coords)
        ..isAntiAlias = true
        ..blendMode = s.eraser ? BlendMode.clear : BlendMode.src
        ..color = s.eraser ? const Color(0x00000000) : const Color(0xFFFFFFFF);

      final path = Path()..moveTo(s.points.first.dx, s.points.first.dy);
      for (int i = 1; i < s.points.length; i++) {
        final a = s.points[i - 1];
        final b = s.points[i];
        final mid = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
        path.quadraticBezierTo(a.dx, a.dy, mid.dx, mid.dy);
      }
      canvas.drawPath(path, p);
    }

    canvas.restore();

    final picture = recorder.endRecording();
    final maskImage = await picture.toImage(img.width, img.height);
    final byteData = await maskImage.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  bool _showSlider = true;
  Timer? _hideTimer;

  void _scheduleHideSlider() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _showSlider = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (_loading) {
      return Scaffold(
        backgroundColor: cs.surface,
        appBar: AppBar(
          title: Text("Draw Mask", style: TextStyle(color: cs.onSurface)),
          backgroundColor: cs.surface,
          iconTheme: IconThemeData(color: cs.onSurface),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_image == null) {
      return Scaffold(
        backgroundColor: cs.surface,
        appBar: AppBar(
          title: Text("Draw Mask", style: TextStyle(color: cs.onSurface)),
          backgroundColor: cs.surface,
          iconTheme: IconThemeData(color: cs.onSurface),
        ),
        body: Center(
          child: Text("Failed to load image",
              style: TextStyle(color: cs.onSurface)),
        ),
      );
    }

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: Text("Draw Mask", style: TextStyle(color: cs.onSurface)),
        backgroundColor: cs.surface,
        iconTheme: IconThemeData(color: cs.onSurface),
        actions: [
          IconButton(
            tooltip: "Undo",
            icon: Icon(Icons.undo, color: cs.onSurface),
            onPressed: () {
              if (_strokes.isNotEmpty) setState(() => _strokes.removeLast());
            },
          ),
          IconButton(
            tooltip: "Clear",
            icon: Icon(Icons.layers_clear, color: cs.onSurface),
            onPressed: () => setState(() => _strokes.clear()),
          ),
          IconButton(
            tooltip: "Toggle Eraser",
            icon: Icon(_eraser ? Icons.brush : Icons.auto_fix_high,
                color: cs.onSurface),
            onPressed: () => setState(() => _eraser = !_eraser),
          ),
          IconButton(
            tooltip: "Save Mask",
            icon: Icon(Icons.check, color: cs.primary),
            onPressed: () async {
              try {
                final maskBytes = await _exportMask();
                Navigator.pop(context, maskBytes);
              } catch (e) {
                debugPrint("Error exporting mask: $e");
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text("Export failed: $e")));
              }
            },
          ),
        ],
      ),
      body: LayoutBuilder(builder: (context, constraints) {
        final widgetSize = Size(constraints.maxWidth,
            constraints.maxHeight - 60); // leave space for ad
        final imgW = _image!.width.toDouble();
        final imgH = _image!.height.toDouble();
        final imgAspect = imgW / imgH;
        final widgetAspect = widgetSize.width / widgetSize.height;

        double displayW, displayH;
        if (imgAspect > widgetAspect) {
          displayW = widgetSize.width;
          displayH = displayW / imgAspect;
        } else {
          displayH = widgetSize.height;
          displayW = displayH * imgAspect;
        }

        final displaySize = Size(displayW, displayH);

        return GestureDetector(
          onTap: () {
            // toggle slider visibility manually on single tap
            setState(() => _showSlider = !_showSlider);
            if (_showSlider) _scheduleHideSlider();
          },
          child: Stack(
            children: [
              // --- MAIN IMAGE + MASK ---
              Positioned.fill(
                top: 0,
                bottom: 60, // reserved for ad
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.contain,
                    child: SizedBox(
                      width: displaySize.width,
                      height: displaySize.height,
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onPanStart: (details) {
                          // hide slider immediately when drawing starts
                          setState(() => _showSlider = false);

                          final local = details.localPosition;

                          final imgPos = _toImageCoords(local, displaySize);
                          _currentStroke = _Stroke(
                            points: [imgPos],
                            size: _brushSize,
                            eraser: _eraser,
                          );
                          setState(() => _strokes.add(_currentStroke!));
                        },
                        onPanUpdate: (details) {
                          final local = details.localPosition;

                          final imgPos = _toImageCoords(local, displaySize);
                          if (_currentStroke != null) {
                            setState(() => _currentStroke!.points.add(imgPos));
                          }
                        },
                        onPanEnd: (_) {
                          _currentStroke = null;
                          _scheduleHideSlider(); // hide again after inactivity
                        },
                        child: ClipRect(
                          child: CustomPaint(
                            painter: _MaskEditorPainter(
                              baseImage: _image!,
                              strokes: _strokes,
                              displaySize: displaySize,
                              maskOverlay: _maskOverlay,
                            ),
                            size: displaySize,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // --- SLIDER (auto-hide with smooth fade) ---
              AnimatedPositioned(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                left: 12,
                right: 12,
                bottom: _showSlider ? 75 : -100, // slide out smoothly
                child: AnimatedOpacity(
                  opacity: _showSlider ? 1 : 0,
                  duration: const Duration(milliseconds: 250),
                  child: IgnorePointer(
                    ignoring: !_showSlider,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: cs.outlineVariant),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.brush, color: cs.onSurfaceVariant),
                          Expanded(
                            child: Slider(
                              value: _brushSize,
                              min: 4,
                              max: 120,
                              onChanged: (v) => setState(() => _brushSize = v),
                              activeColor: cs.primary,
                              inactiveColor:
                                  cs.onSurfaceVariant.withOpacity(0.3),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text("${_brushSize.toInt()}",
                              style: TextStyle(color: cs.onSurfaceVariant)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // --- OPTIONAL AD BANNER ---
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: 60,
                child: Container(
                  color: Colors.black12,
                  alignment: Alignment.center,
                  child: Text("Ad Banner",
                      style: TextStyle(color: Colors.black54)),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}

// small helper data class
class _Stroke {
  final List<Offset> points;
  final double size;
  final bool eraser;
  _Stroke({required this.points, required this.size, required this.eraser});
}

/// Painter used inside MaskEditorPage to show base image and overlay strokes scaled to the display size.
class _MaskEditorPainter extends CustomPainter {
  final ui.Image baseImage;
  final ui.Image? maskOverlay;

  final List<_Stroke> strokes;
  final Size displaySize;

  _MaskEditorPainter({
    required this.baseImage,
    required this.strokes,
    required this.displaySize,
    this.maskOverlay,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final dst = Rect.fromLTWH(0, 0, displaySize.width, displaySize.height);
    paintImage(canvas: canvas, rect: dst, image: baseImage, fit: BoxFit.fill);

    final sx = displaySize.width / baseImage.width.toDouble();
    final sy = displaySize.height / baseImage.height.toDouble();

    // --- Build the red overlay by COMPOSITING mask + strokes together ---
    if (maskOverlay != null || strokes.isNotEmpty) {
      // 1) New layer to hold: (existing mask) +/- (strokes with erase)
      canvas.saveLayer(dst, Paint());

      // 1a) Draw the existing mask into the layer (scaled to dst)
      if (maskOverlay != null) {
        final src = Rect.fromLTWH(
          0,
          0,
          maskOverlay!.width.toDouble(),
          maskOverlay!.height.toDouble(),
        );
        // draw as pure alpha (no tint yet)
        final paintSrc = Paint()..blendMode = BlendMode.src;
        canvas.drawImageRect(maskOverlay!, src, dst, paintSrc);
      }

      // 1b) Apply strokes on the SAME layer so clear erases old mask too
      for (final s in strokes) {
        if (s.points.length < 2) continue;

        final strokeWidth = s.size * ((sx + sy) / 2);

        final p = Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = strokeWidth
          ..isAntiAlias = true
          ..blendMode = s.eraser ? BlendMode.clear : BlendMode.srcOver
          ..color = s.eraser
              ? const Color(0x00000000)
              : const Color(0xFFFFFFFF); // white = add to mask alpha

        final path = Path()
          ..moveTo(s.points.first.dx * sx, s.points.first.dy * sy);
        for (int i = 1; i < s.points.length; i++) {
          final a = s.points[i - 1];
          final b = s.points[i];
          final mid = Offset((a.dx + b.dx) / 2 * sx, (a.dy + b.dy) / 2 * sy);
          path.quadraticBezierTo(a.dx * sx, a.dy * sy, mid.dx, mid.dy);
        }
        canvas.drawPath(path, p);
      }

      // 2) Tint the current layer’s alpha in red so user sees the mask area
      final tint = Paint()
        ..color = const Color(0x55FF0000)
        ..blendMode = BlendMode.srcIn;
      canvas.drawRect(dst, tint);

      // 3) Flatten back
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _MaskEditorPainter oldDelegate) => true;
}
