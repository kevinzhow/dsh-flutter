#include "native_html.h"
#include <webkit2/webkit2.h>
#include <map>
#include <cstdint>
#include <algorithm>

namespace {
struct HtmlViews {
  GtkWidget* layer;
  FlMethodChannel* channel;
  std::map<int64_t, GtkWidget*> views;
};
struct HtmlIdentity { HtmlViews* owner; int64_t id; };
static void failure(WebKitWebView*, WebKitWebProcessTerminationReason, gpointer data) {
  auto* identity = static_cast<HtmlIdentity*>(data);
  g_autoptr(FlValue) value = fl_value_new_int(identity->id);
  fl_method_channel_invoke_method(identity->owner->channel, "failed", value, nullptr, nullptr, nullptr);
}
static gboolean deny_permission(WebKitWebView*, WebKitPermissionRequest* request, gpointer) {
  webkit_permission_request_deny(request);
  return TRUE;
}
static gboolean policy(WebKitWebView*, WebKitPolicyDecision* decision, WebKitPolicyDecisionType type, gpointer) {
  if (type == WEBKIT_POLICY_DECISION_TYPE_NEW_WINDOW_ACTION) {
    webkit_policy_decision_ignore(decision);
    return TRUE;
  }
  if (type == WEBKIT_POLICY_DECISION_TYPE_NAVIGATION_ACTION) {
    auto* action = webkit_navigation_policy_decision_get_navigation_action(WEBKIT_NAVIGATION_POLICY_DECISION(decision));
    const char* uri = webkit_uri_request_get_uri(webkit_navigation_action_get_request(action));
    // Browsing stays inside the sandboxed document; never navigate the native
    // view to a Host URL, a local file, another application or a downloaded file.
    if (uri && !g_str_has_prefix(uri, "about:") && !g_str_has_prefix(uri, "blob:") && !g_str_has_prefix(uri, "data:")) {
      webkit_policy_decision_ignore(decision);
      return TRUE;
    }
  }
  return FALSE;
}
static void deny_download(WebKitWebContext*, WebKitDownload* download, gpointer) {
  webkit_download_cancel(download);
}
static double number(FlValue* args, const char* key) {
  FlValue* value = fl_value_lookup_string(args, key);
  if (!value) return 0;
  if (fl_value_get_type(value) == FL_VALUE_TYPE_FLOAT) return fl_value_get_float(value);
  if (fl_value_get_type(value) == FL_VALUE_TYPE_INT) return static_cast<double>(fl_value_get_int(value));
  return 0;
}
static void respond(FlMethodCall* call, FlMethodResponse* response) {
  g_autoptr(GError) error = nullptr;
  fl_method_call_respond(call, response, &error);
}
static void handle(FlMethodChannel*, FlMethodCall* call, gpointer data) {
  auto* owner = static_cast<HtmlViews*>(data);
  const char* method = fl_method_call_get_name(call);
  FlValue* args = fl_method_call_get_args(call);
  if (!args || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
    g_autoptr(FlMethodResponse) response = FL_METHOD_RESPONSE(fl_method_error_response_new("invalid-arguments", "HTML view arguments are missing", nullptr));
    respond(call, response); return;
  }
  int64_t id = static_cast<int64_t>(number(args, "id"));
  if (g_strcmp0(method, "create") == 0) {
    FlValue* html = fl_value_lookup_string(args, "html");
    if (owner->views.count(id) || !html || fl_value_get_type(html) != FL_VALUE_TYPE_STRING) {
      g_autoptr(FlMethodResponse) response = FL_METHOD_RESPONSE(fl_method_error_response_new("invalid-view", "HTML view identity or content is invalid", nullptr));
      respond(call, response); return;
    }
    WebKitWebContext* context = webkit_web_context_new_ephemeral();
    GtkWidget* browser = webkit_web_view_new_with_context(context);
    g_signal_connect(context, "download-started", G_CALLBACK(deny_download), nullptr);
    g_object_unref(context);
    g_object_ref_sink(browser);
    WebKitSettings* settings = webkit_web_view_get_settings(WEBKIT_WEB_VIEW(browser));
    webkit_settings_set_allow_file_access_from_file_urls(settings, FALSE);
    webkit_settings_set_allow_universal_access_from_file_urls(settings, FALSE);
    webkit_settings_set_enable_developer_extras(settings, FALSE);
    webkit_settings_set_hardware_acceleration_policy(settings, WEBKIT_HARDWARE_ACCELERATION_POLICY_ALWAYS);
    g_signal_connect(browser, "permission-request", G_CALLBACK(deny_permission), nullptr);
    g_signal_connect(browser, "decide-policy", G_CALLBACK(policy), nullptr);
    auto* identity = new HtmlIdentity{owner, id};
    g_object_set_data_full(G_OBJECT(browser), "html-identity", identity, [](gpointer p) { delete static_cast<HtmlIdentity*>(p); });
    g_signal_connect(browser, "web-process-terminated", G_CALLBACK(failure), identity);
    gtk_widget_set_halign(browser, GTK_ALIGN_START);
    gtk_widget_set_valign(browser, GTK_ALIGN_START);
    gtk_overlay_add_overlay(GTK_OVERLAY(owner->layer), browser);
    owner->views[id] = browser;
    webkit_web_view_load_html(WEBKIT_WEB_VIEW(browser), fl_value_get_string(html), "about:blank");
  } else if (g_strcmp0(method, "bounds") == 0) {
    auto found = owner->views.find(id);
    if (found != owner->views.end()) {
      GtkWidget* browser = found->second;
      int width = std::max(0, static_cast<int>(number(args, "width")));
      int height = std::max(0, static_cast<int>(number(args, "height")));
      if (width == 0 || height == 0) gtk_widget_hide(browser);
      else {
        gtk_widget_set_margin_start(browser, std::max(0, static_cast<int>(number(args, "x"))));
        gtk_widget_set_margin_top(browser, std::max(0, static_cast<int>(number(args, "y"))));
        gtk_widget_set_size_request(browser, width, height);
        gtk_widget_show(browser);
      }
    }
  } else if (g_strcmp0(method, "dispose") == 0) {
    auto found = owner->views.find(id);
    if (found != owner->views.end()) {
      gtk_widget_destroy(found->second); g_object_unref(found->second); owner->views.erase(found);
    }
  } else {
    g_autoptr(FlMethodResponse) response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
    respond(call, response); return;
  }
  g_autoptr(FlMethodResponse) response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  respond(call, response);
}
}
void whalee_native_html_register(FlView* view, GtkWidget* overlay) {
  auto* owner = new HtmlViews{};
  owner->layer = overlay;
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  owner->channel = fl_method_channel_new(fl_engine_get_binary_messenger(fl_view_get_engine(view)), "app.kevinzhow.whalee/html", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(owner->channel, handle, owner, nullptr);
  g_object_set_data_full(G_OBJECT(view), "whalee-native-html", owner, [](gpointer data) {
    auto* state = static_cast<HtmlViews*>(data);
    fl_method_channel_set_method_call_handler(state->channel, nullptr, nullptr, nullptr);
    for (const auto& entry : state->views) { gtk_widget_destroy(entry.second); g_object_unref(entry.second); }
    g_object_unref(state->channel); delete state;
  });
}
