import os
import logging
import datetime
import Cookie
import urllib

from google.appengine.api import users
from google.appengine.ext import webapp
from google.appengine.ext.webapp import template
from google.appengine.runtime.apiproxy_errors import CapabilityDisabledError

from custom_exceptions import MissingVideoException, MissingExerciseException
import util
from app import App
from models import UserData

class RequestHandler(webapp.RequestHandler):

    def request_string(self, key, default = ''):
        return self.request.get(key, default_value=default)

    def request_int(self, key, default = None):
        try:
            return int(self.request_string(key))
        except ValueError:
            if default is not None:
                return default
            else:
                raise # No value available and no default supplied, raise error

    def request_date(self, key, format_string, default = None):
        try:
            return datetime.datetime.strptime(self.request_string(key), format_string)
        except ValueError:
            if default is not None:
                return default
            else:
                raise # No value available and no default supplied, raise error

    def request_float(self, key, default = None):
        try:        
            return float(self.request_string(key))
        except ValueError:
            if default is not None:
                return default
            else:
                raise # No value available and no default supplied, raise error

    def request_bool(self, key, default = None):
        if default is None:
            return self.request_int(key) == 1
        else:
            return self.request_int(key, 1 if default else 0) == 1

    def is_ajax_request(self):
        # jQuery sets X-Requested-With header for this detection.
        if self.request.headers.has_key("x-requested-with"):
            s_requested_with = self.request.headers["x-requested-with"]
            if s_requested_with and s_requested_with.lower() == "xmlhttprequest":
                return True
        return self.request_bool("is_ajax_override", default=False)

    def request_url_with_additional_query_params(self, params):
        url = self.request.url
        if url.find("?") > -1:
            url += "&"
        else:
            url += "?"
        return url + params

    def handle_exception(self, e, *args):

        silence_report = False

        title = "Oops. We broke our streak."
        message_html = "We ran into a problem. It's our fault, and we're working on it."
        sub_message_html = "This has been reported to us, and we'll be looking for a fix. If the problem continues, feel free to <a href='/reportissue?type=Defect'>send us a report directly</a>."

        if type(e) is CapabilityDisabledError:

            # App Engine maintenance period
            message_html = "We're temporarily down for maintenance. Try again in about an hour. We're sorry for the inconvenience."

        elif type(e) is MissingExerciseException:

            title = "This exercise isn't here right now."
            message_html = "Either this exercise doesn't exist or it's temporarily hiding. You should <a href='/exercisedashboard'>head back to our other exercises</a>."
            sub_message_html = "If this problem continues and you think something is wrong, please <a href='/reportissue?type=Defect'>let us know by sending a report</a>."

        elif type(e) is MissingVideoException:

            # We don't log missing videos as errors because they're so common due to malformed URLs or renamed videos.
            # Ask users to report any significant problems, and log as info in case we need to research.
            silence_report = True
            logging.info(e)
            title = "This video is no longer around."
            message_html = "You're looking for a video that either never existed or wandered away. <a href='/'>Head to our video library</a> to find it."
            sub_message_html = "If this problem continues and you think something is wrong, please <a href='/reportissue?type=Defect'>let us know by sending a report</a>."

        if not silence_report:
            webapp.RequestHandler.handle_exception(self, e, args)

        # Never show stack traces on production machines
        if not App.is_dev_server:
            self.response.clear()

        self.render_template('viewerror.html', { "title": title, "message_html": message_html, "sub_message_html": sub_message_html })

    def user_agent(self):
        return str(self.request.headers['User-Agent'])

    def is_mobile(self):
        user_agent_lower = self.user_agent().lower()
        return user_agent_lower.find("ipod") > -1 or \
                user_agent_lower.find("ipad") > -1 or \
                user_agent_lower.find("iphone") > -1 or \
                user_agent_lower.find("webos") > -1 or \
                user_agent_lower.find("android") > -1

    # Cookie handling from http://appengine-cookbook.appspot.com/recipe/a-simple-cookie-class/
    def set_cookie(self, key, value='', max_age=None,
                   path='/', domain=None, secure=None, httponly=False,
                   version=None, comment=None):
        cookies = Cookie.BaseCookie()
        cookies[key] = value
        for var_name, var_value in [
            ('max-age', max_age),
            ('path', path),
            ('domain', domain),
            ('secure', secure),
            ('HttpOnly', httponly),
            ('version', version),
            ('comment', comment),
            ]:
            if var_value is not None and var_value is not False:
                cookies[key][var_name] = str(var_value)
            if max_age is not None:
                cookies[key]['expires'] = max_age
        header_value = cookies[key].output(header='').lstrip()
        self.response.headers._headers.append(('Set-Cookie', header_value))

    def delete_cookie(self, key, path='/', domain=None):
        self.set_cookie(key, '', path=path, domain=domain, max_age=0)

    def render_template(self, template_name, template_values):
        template_values['App'] = App
        template_values['None'] = None
        template_values['points'] = None
        template_values['username'] = ""

        user = util.get_current_user()
        if user is not None:
            template_values['username'] = user.nickname()

        user_data = UserData.get_for(user)

        template_values['user_data'] = user_data
        template_values['points'] = user_data.points if user_data else 0

        if not template_values.has_key('continue'):
            template_values['continue'] = self.request.uri

        # Always insert a post-login request before our continue url
        template_values['continue'] = util.create_post_login_url(template_values['continue'])

        template_values['login_url'] = ('%s&direct=1' % util.create_login_url(template_values['continue']))
        template_values['logout_url'] = util.create_logout_url(self.request.uri)

        template_values['is_mobile'] = self.is_mobile()

        path = os.path.join(os.path.dirname(__file__), template_name)
        self.response.out.write(template.render(path, template_values))
 
